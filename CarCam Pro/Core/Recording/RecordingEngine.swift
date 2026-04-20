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
                audioEnabled: settings.audioEnabled && !isMuted
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

            // Start first segment
            _ = try manager.startFirstSegment()

            // Wire sample buffer bridge
            sampleBufferBridge.segmentManager = manager
            await cameraService.setSampleBufferDelegate(sampleBufferBridge)

            // Save session to SwiftData
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
            throw error
        }
    }

    func stopRecording() async throws {
        guard state.isRecording else { return }

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

        // Update session
        if let session = currentSession, let modelContainer {
            session.endDate = Date()
            session.totalDuration = currentDuration
            session.totalSegments = currentSegment

            let context = ModelContext(modelContainer)
            context.insert(session)
            try? context.save()
        }

        segmentManager = nil
        currentSession = nil
        currentSegment = 0
        currentDuration = 0

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
