import AVFoundation
import SwiftData
import SwiftUI
import OSLog

@Observable
@MainActor
final class RecordingEngine {
    private(set) var state: RecordingState = .idle
    private(set) var currentDuration: TimeInterval = 0
    private(set) var currentSegment: Int = 0
    private(set) var isMuted: Bool = false

    private let cameraService: CameraService
    private var modelContainer: ModelContainer?
    private var storageManager: StorageManager?
    private var segmentManager: SegmentManager?
    private var currentSession: RecordingSession?
    private var durationTimer: Timer?
    private let sampleBufferBridge: SegmentedSampleBufferBridge

    init(cameraService: CameraService) {
        self.cameraService = cameraService
        self.sampleBufferBridge = SegmentedSampleBufferBridge()
    }

    func configure(modelContainer: ModelContainer, storageManager: StorageManager) {
        self.modelContainer = modelContainer
        self.storageManager = storageManager
    }

    // MARK: - Public API

    func startRecording() async throws {
        guard state.isIdle else {
            throw RecordingError.alreadyRecording
        }

        state = .starting

        do {
            // Activate the audio session BEFORE configuring the camera. The
            // capture session reads the active audio category when
            // installing its audio output — starting with `.playAndRecord`
            // already set gets us bluetooth + background capture without a
            // mid-session reconfigure.
            let audioEnabled = AppSettings.shared.audioEnabled && !isMuted
            try AudioSessionManager.shared.activate(allowAudioCapture: audioEnabled)
            installAudioSessionCallbacksIfNeeded()
            installCameraInterruptionCallbacksIfNeeded()

            // Ensure camera is configured and running
            if !cameraService.isRunning {
                let config = CameraConfiguration.default
                try await cameraService.configure(config)
                try await cameraService.startCapture()
            }

            // Create session
            let session = RecordingSession()
            let sessionDir = FileSystemManager.sessionDirectory(
                date: session.startDate,
                sessionID: session.id
            )

            // Create segment manager
            let settings = AppSettings.shared
            let manager = SegmentManager(
                segmentDuration: settings.segmentDuration,
                sessionShortID: session.shortID,
                sessionDirectory: sessionDir,
                modelContainer: modelContainer,
                sessionID: session.id,
                audioEnabled: audioEnabled
            )

            // Listen for segment completions — enforce storage cap after each rotation
            let storageRef = storageManager
            manager.onSegmentCompleted = { [weak self] segmentIndex in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentSegment = segmentIndex + 1
                    self.state = .recording(segment: self.currentSegment, duration: self.currentDuration)
                }
                // Enforce storage cap in background
                Task.detached {
                    try? await storageRef?.enforceStorageCap()
                }
            }

            // A terminal writer failure (disk full, media-services reset,
            // asset-writer .failed) stops the session so we don't keep
            // pretending to record. Surfaces as `.error` state in the UI.
            manager.onWriterFailure = { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    AppLogger.recording.error(
                        "Writer failure — stopping session: \(error.localizedDescription)"
                    )
                    self.state = .error(.writerSetupFailed(error.localizedDescription))
                    try? await self.stopRecording()
                }
            }

            // Start first segment
            _ = try manager.startFirstSegment()

            // Wire sample buffer bridge
            sampleBufferBridge.segmentManager = manager
            await cameraService.setSampleBufferDelegate(sampleBufferBridge)

            // Save session to SwiftData (one-time insert at start).
            if let modelContainer {
                let context = ModelContext(modelContainer)
                context.insert(session)
                try context.save()
            }

            segmentManager = manager
            currentSession = session
            currentSegment = 1
            currentDuration = 0

            // Start duration timer
            startDurationTimer()

            state = .recording(segment: 1, duration: 0)
            AppLogger.recording.info("Recording started: session \(session.shortID)")

        } catch {
            state = .error(.writerSetupFailed(error.localizedDescription))
            AudioSessionManager.shared.deactivate()
            throw error
        }
    }

    func stopRecording() async throws {
        // Allow stopping from .error or .recording; no-op otherwise.
        guard state.isRecording || state.isError else { return }

        state = .stopping
        stopDurationTimer()

        // Stop the bridge from sending buffers
        sampleBufferBridge.segmentManager = nil

        // Finalize current segment
        if let manager = segmentManager {
            do {
                _ = try await manager.stopCurrentSegment()
            } catch {
                AppLogger.recording.error("Failed to finalize segment: \(error.localizedDescription)")
            }
        }

        // Update the already-inserted session in place — don't re-insert;
        // SwiftData would cascade-orphan the newly-created clips.
        if let session = currentSession, let modelContainer {
            session.endDate = Date()
            session.totalDuration = currentDuration
            session.totalSegments = currentSegment

            let context = ModelContext(modelContainer)
            try? context.save()
            _ = modelContainer // silence unused-warning in minimal builds
        }

        segmentManager = nil
        currentSession = nil
        currentSegment = 0
        currentDuration = 0

        AudioSessionManager.shared.deactivate()

        state = .idle
        AppLogger.recording.info("Recording stopped")
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func reset() {
        state = .idle
        currentDuration = 0
        currentSegment = 0
    }

    // MARK: - Thermal / location / incident integration

    /// Last-applied thermal tier — exposed so UI (settings, dashboards) can
    /// render the current policy without a separate observation.
    private(set) var activeTier: ThermalTier = .nominal

    /// Last observed location sample (stamped onto each clip finalization).
    private(set) var lastLocationSample: LocationSample?

    /// Whether the parking sentry is armed. When true, the engine keeps the
    /// capture session warm and starts a new session automatically in
    /// response to an incident event while idle.
    private(set) var parkingSentryEnabled: Bool = false

    func setParkingSentryEnabled(_ enabled: Bool) {
        parkingSentryEnabled = enabled
    }

    /// Current session's drive distance (miles). 0 when idle.
    var currentSessionMiles: Double { sessionDistanceMeters / 1609.344 }

    /// Active recording session's distance accumulator (meters).
    private var sessionDistanceMeters: Double = 0
    private var sessionPeakMPH: Double = 0
    private var sessionIncidentCount: Int = 0
    private var sessionLockedCount: Int = 0
    private var lastLocationForDistance: LocationSample?

    /// Apply a thermal tier — adjusts the camera pipeline, framerate, and
    /// bitrate without tearing down the capture session.
    func applyThermalTier(_ tier: ThermalTier) {
        activeTier = tier
        cameraService.applyThermalPolicy(
            maxFrameRate: tier.maxFrameRate,
            bitrateMultiplier: tier.bitrateMultiplier,
            forcedResolutionCeiling: tier.forcedResolutionCeiling
        )
        AppLogger.recording.info("Applied thermal tier to pipeline: \(tier.label)")
    }

    /// Tag the current clip as protected ("locked"). Called from the live HUD
    /// `LOCK` button or in response to an incident event.
    func protectCurrentClip() async {
        guard let session = currentSession else { return }
        sessionLockedCount += 1
        session.lockedClipCount = sessionLockedCount
        await storageManager?.protectLatestClip(
            in: session.id,
            reason: .manualProtect
        )
        AppLogger.recording.notice("Clip locked by user (session \(session.shortID))")
    }

    /// Handle an incident detector event — protect the active clip +/- the
    /// configured context window. Skipped when not recording.
    func handleIncident(_ event: IncidentEvent) {
        guard let session = currentSession else { return }
        sessionIncidentCount += 1
        session.incidentCount = sessionIncidentCount
        Task { [storageManager, session] in
            await storageManager?.protectLatestClip(
                in: session.id,
                reason: .incidentDetected
            )
        }
        AppLogger.recording.notice("Incident protected: \(event.severity.rawValue) @ \(event.totalG)g")
    }

    /// Ingest a new location sample — drives the HUD readout and accumulates
    /// trip metrics on the active session.
    func ingestLocation(_ sample: LocationSample) {
        lastLocationSample = sample

        if let speedMPH = sample.speedMPH {
            sessionPeakMPH = max(sessionPeakMPH, speedMPH)
            currentSession?.peakSpeedMPH = sessionPeakMPH
        }

        if let previous = lastLocationForDistance {
            let deltaMeters = distance(from: previous, to: sample)
            if deltaMeters > 1 && deltaMeters < 200 {
                sessionDistanceMeters += deltaMeters
                currentSession?.totalDistanceMeters = sessionDistanceMeters
            }
        }
        lastLocationForDistance = sample
    }

    private func distance(from a: LocationSample, to b: LocationSample) -> Double {
        let earthR = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let sdLat = sin(dLat / 2)
        let sdLon = sin(dLon / 2)
        let h = sdLat * sdLat + cos(lat1) * cos(lat2) * sdLon * sdLon
        return 2 * earthR * atan2(sqrt(h), sqrt(1 - h))
    }

    // MARK: - Interruption plumbing

    private var audioCallbacksInstalled = false
    private var cameraCallbacksInstalled = false

    private func installAudioSessionCallbacksIfNeeded() {
        guard !audioCallbacksInstalled else { return }
        audioCallbacksInstalled = true

        let audio = AudioSessionManager.shared
        audio.onInterruptionBegan = { [weak self] in
            AppLogger.recording.notice("Audio interruption began — pausing writers")
            // We leave the capture session alive but stop feeding buffers
            // to the writer bridge; the next sample after resume will drop
            // into the same segment so we get a short silence, not a file
            // corruption.
            self?.sampleBufferBridge.segmentManager = nil
        }
        audio.onInterruptionEnded = { [weak self] in
            AppLogger.recording.notice("Audio interruption ended — resuming writers")
            guard let self, let manager = self.segmentManager else { return }
            self.sampleBufferBridge.segmentManager = manager
        }
        audio.onMediaServicesReset = { [weak self] in
            AppLogger.recording.error("Audio media services reset — stopping session")
            Task { @MainActor [weak self] in
                self?.state = .error(.writerSetupFailed("audio media services reset"))
                try? await self?.stopRecording()
            }
        }
        audio.onRouteChanged = { reason in
            // No action needed for most reasons — logged centrally in
            // AudioSessionManager. If we get `.oldDeviceUnavailable` while
            // recording (e.g. BT mic dropped), the next segment will
            // reconfigure the session with whatever mic is available.
            _ = reason
        }
    }

    private func installCameraInterruptionCallbacksIfNeeded() {
        guard !cameraCallbacksInstalled else { return }
        cameraCallbacksInstalled = true

        cameraService.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                AppLogger.recording.notice("Capture interrupted — pausing writers")
                self?.sampleBufferBridge.segmentManager = nil
            }
        }
        cameraService.onInterruptionEnded = { [weak self] in
            Task { @MainActor [weak self] in
                AppLogger.recording.notice("Capture resumed — reattaching writers")
                guard let self, let manager = self.segmentManager else { return }
                self.sampleBufferBridge.segmentManager = manager
            }
        }
        cameraService.onRuntimeError = { [weak self] error in
            Task { @MainActor [weak self] in
                AppLogger.recording.error(
                    "Capture runtime error: \(error?.localizedDescription ?? "nil")"
                )
                // The CameraService already attempts restart. If we're
                // recording, mark an error + stop so the UI can resurface.
                guard let self, self.state.isRecording else { return }
                self.state = .error(.writerSetupFailed(error?.localizedDescription ?? "capture runtime error"))
                try? await self.stopRecording()
            }
        }
    }

    // MARK: - Private

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.state.isRecording else { return }
                self.currentDuration += 1
                self.currentSegment = self.segmentManager?.currentSegmentIndex ?? self.currentSegment
                self.state = .recording(segment: self.currentSegment, duration: self.currentDuration)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Formatted Duration

    var formattedDuration: String {
        let hours = Int(currentDuration) / 3600
        let minutes = (Int(currentDuration) % 3600) / 60
        let seconds = Int(currentDuration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Writer Proxy (thread-safe wrapper for camera queue access)

final class WriterProxy: @unchecked Sendable {
    let writer: VideoWriter
    private var hasStartedSession = false

    init(writer: VideoWriter) {
        self.writer = writer
    }

    func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if !hasStartedSession {
            let sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            do {
                try writer.start(atSourceTime: sourceTime)
                hasStartedSession = true
            } catch {
                AppLogger.recording.error("Failed to start writer: \(error.localizedDescription)")
                return
            }
        }
        writer.appendVideoBuffer(sampleBuffer)
    }

    func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard hasStartedSession, writer.isWriting else { return }
        writer.appendAudioBuffer(sampleBuffer)
    }
}

// MARK: - Segmented Sample Buffer Bridge

final class SegmentedSampleBufferBridge: SampleBufferDelegate, @unchecked Sendable {
    var segmentManager: SegmentManager?

    func didOutputVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        segmentManager?.processSampleBuffer(sampleBuffer, isVideo: true)
    }

    func didOutputAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        segmentManager?.processSampleBuffer(sampleBuffer, isVideo: false)
    }
}
