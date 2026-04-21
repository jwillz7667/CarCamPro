import AVFoundation
import OSLog

final class CameraService: NSObject, CameraServiceProtocol, @unchecked Sendable {
    let captureSession = AVCaptureSession()

    private let cameraQueue = DispatchQueue(label: "res.carcam-pro.camera", qos: .userInteractive)
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var currentConfig: CameraConfiguration?
    private nonisolated(unsafe) weak var sampleDelegate: (any SampleBufferDelegate)?

    private(set) var isRunning = false

    // MARK: - Interruption handling

    /// Caller-supplied hook fired when the capture session is interrupted
    /// (phone call, PiP, another camera-using app foregrounding, etc.).
    /// Recording engines should pause writers but keep the session warm.
    nonisolated(unsafe) var onInterruptionBegan: (@Sendable () -> Void)?
    /// Fires when the interruption ends. Engines should cut a fresh
    /// segment if one was rotating, or resume writing to the current one.
    nonisolated(unsafe) var onInterruptionEnded: (@Sendable () -> Void)?
    /// Fires on `runtimeErrorNotification`. Unlike interruptions, this
    /// usually requires a full session restart. We attempt an automatic
    /// restart via `cameraQueue.async { captureSession.startRunning() }`
    /// but also notify the caller so it can resurface the session errored
    /// state in the UI.
    nonisolated(unsafe) var onRuntimeError: (@Sendable (Error?) -> Void)?

    private var interruptionObservers: [NSObjectProtocol] = []

    // MARK: - Configuration

    func configure(_ config: CameraConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cameraQueue.async { [self] in
                do {
                    try configureSynchronously(config)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureSynchronously(_ config: CameraConfiguration) throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Remove existing inputs
        if let videoInput = videoDeviceInput {
            captureSession.removeInput(videoInput)
            videoDeviceInput = nil
        }
        if let audioInput = audioDeviceInput {
            captureSession.removeInput(audioInput)
            audioDeviceInput = nil
        }

        // Remove existing outputs
        if let videoOutput = videoDataOutput {
            captureSession.removeOutput(videoOutput)
            videoDataOutput = nil
        }
        if let audioOutput = audioDataOutput {
            captureSession.removeOutput(audioOutput)
            audioDataOutput = nil
        }

        // Set session preset
        let preset = sessionPreset(for: config.resolution)
        if captureSession.canSetSessionPreset(preset) {
            captureSession.sessionPreset = preset
        } else {
            throw CameraError.configurationFailed("Unsupported resolution: \(config.resolution.rawValue)")
        }

        // Add video input
        let device = try captureDevice(for: config.cameraPosition)
        let videoInput = try AVCaptureDeviceInput(device: device)

        guard captureSession.canAddInput(videoInput) else {
            throw CameraError.configurationFailed("Cannot add video input")
        }
        captureSession.addInput(videoInput)
        videoDeviceInput = videoInput

        // Configure frame rate
        try configureFrameRate(device: device, frameRate: config.frameRate)

        // Add audio input if enabled
        if config.audioEnabled, let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                    audioDeviceInput = audioInput
                }
            } catch {
                AppLogger.camera.warning("Could not add audio input: \(error.localizedDescription)")
            }
        }

        // Add video data output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraError.configurationFailed("Cannot add video output")
        }
        captureSession.addOutput(videoOutput)
        videoDataOutput = videoOutput

        // Add audio data output if audio input was added
        if audioDeviceInput != nil {
            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: cameraQueue)
            if captureSession.canAddOutput(audioOutput) {
                captureSession.addOutput(audioOutput)
                audioDataOutput = audioOutput
            }
        }

        currentConfig = config
        AppLogger.camera.info("Camera configured: \(config.resolution.rawValue) @ \(config.frameRate)fps, \(config.codec.rawValue)")
    }

    // MARK: - Capture Control

    func startCapture() async throws {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraError.notAuthorized }
        case .authorized:
            break
        default:
            throw CameraError.notAuthorized
        }

        installInterruptionObserversIfNeeded()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cameraQueue.async { [self] in
                if !captureSession.isRunning {
                    captureSession.startRunning()
                    isRunning = true
                    AppLogger.camera.info("Capture session started")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Capture-session interruption observers

    /// Install once per process — the observers live for the lifetime of the
    /// `CameraService` instance (which is process-scoped via the
    /// `DependencyContainer`).
    private func installInterruptionObserversIfNeeded() {
        guard interruptionObservers.isEmpty else { return }
        let center = NotificationCenter.default

        // 1. AVCaptureSessionWasInterrupted — phone call, PiP, another app
        //    took the camera, resource constraints, etc.
        interruptionObservers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: nil
        ) { [weak self] note in
            self?.handleInterruptionBegan(note)
        })

        // 2. AVCaptureSessionInterruptionEnded — paired with the above.
        interruptionObservers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: captureSession,
            queue: nil
        ) { [weak self] _ in
            self?.handleInterruptionEnded()
        })

        // 3. AVCaptureSessionRuntimeError — mic lost, media services dead, ...
        interruptionObservers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: captureSession,
            queue: nil
        ) { [weak self] note in
            self?.handleRuntimeError(note)
        })
    }

    private func handleInterruptionBegan(_ note: Notification) {
        let reasonValue = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? -1
        AppLogger.camera.notice("Capture session interrupted (reason=\(reasonValue))")
        onInterruptionBegan?()
    }

    private func handleInterruptionEnded() {
        AppLogger.camera.notice("Capture session interruption ended")
        cameraQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                self.isRunning = self.captureSession.isRunning
            }
        }
        onInterruptionEnded?()
    }

    private func handleRuntimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
        AppLogger.camera.error(
            "Capture session runtime error: \(error?.localizedDescription ?? "nil")"
        )
        // Attempt an automatic restart. The session object itself is still
        // valid after a runtime error — only `startRunning()` needs to be
        // re-invoked. If the underlying issue is persistent we'll bounce
        // here repeatedly, which is logged each time; the engine surfaces
        // the error in state so the UI can show a "camera lost" banner.
        cameraQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.startRunning()
            self.isRunning = self.captureSession.isRunning
        }
        onRuntimeError?(error)
    }

    func stopCapture() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cameraQueue.async { [self] in
                if captureSession.isRunning {
                    captureSession.stopRunning()
                    isRunning = false
                    AppLogger.camera.info("Capture session stopped")
                }
                continuation.resume()
            }
        }
    }

    func switchCamera(to position: CameraPosition) async throws {
        guard var config = currentConfig else {
            throw CameraError.configurationFailed("No current configuration")
        }
        config = CameraConfiguration(
            resolution: config.resolution,
            frameRate: config.frameRate,
            codec: config.codec,
            cameraPosition: position,
            audioEnabled: config.audioEnabled
        )
        try await configure(config)
    }

    func updateQuality(resolution: VideoResolution, frameRate: Int, bitrate: Int) async throws {
        guard var config = currentConfig else {
            throw CameraError.configurationFailed("No current configuration")
        }
        config = CameraConfiguration(
            resolution: resolution,
            frameRate: frameRate,
            codec: config.codec,
            cameraPosition: config.cameraPosition,
            audioEnabled: config.audioEnabled
        )
        try await configure(config)
    }

    func setSampleBufferDelegate(_ delegate: any SampleBufferDelegate) async {
        sampleDelegate = delegate
    }

    // MARK: - Permission Check

    static func checkAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - Private Helpers

    private func captureDevice(for position: CameraPosition) throws -> AVCaptureDevice {
        if position == .front {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                throw CameraError.deviceUnavailable(position)
            }
            return device
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        )

        let device = discoverySession.devices.first { $0.deviceType == position.deviceType }
        guard let device else {
            throw CameraError.deviceUnavailable(position)
        }
        return device
    }

    private func configureFrameRate(device: AVCaptureDevice, frameRate: Int) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let frameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
    }

    /// Apply a thermal policy without tearing down the session. Framerate is
    /// clamped against the active device's min/max supported range; bitrate is
    /// stored for the next segment's writer to pick up.
    func applyThermalPolicy(
        maxFrameRate: Int,
        bitrateMultiplier: Double,
        forcedResolutionCeiling: VideoResolution?
    ) {
        cameraQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            let targetFPS = min(maxFrameRate, self.currentConfig?.frameRate ?? maxFrameRate)
            do {
                try self.configureFrameRate(device: device, frameRate: targetFPS)
            } catch {
                AppLogger.camera.error("Failed to throttle framerate: \(error.localizedDescription)")
            }
            self.bitrateMultiplier = bitrateMultiplier

            // Resolution ceiling — only downshift if currently higher.
            if let ceiling = forcedResolutionCeiling,
               let current = self.currentConfig,
               current.resolution.rawValue != ceiling.rawValue,
               self.resolutionRank(ceiling) < self.resolutionRank(current.resolution) {
                var scaled = current
                scaled = CameraConfiguration(
                    resolution: ceiling,
                    frameRate: targetFPS,
                    codec: current.codec,
                    cameraPosition: current.cameraPosition,
                    audioEnabled: current.audioEnabled
                )
                do {
                    try self.configureSynchronously(scaled)
                    AppLogger.camera.info("Downshifted resolution to \(ceiling.rawValue) for thermal policy")
                } catch {
                    AppLogger.camera.error("Thermal resolution downshift failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Currently-applied bitrate multiplier (consumed by VideoWriter when a
    /// new segment rolls over). Default 1.0 = user-configured bitrate.
    private(set) var bitrateMultiplier: Double = 1.0

    private func resolutionRank(_ r: VideoResolution) -> Int {
        switch r {
        case .hd720: return 0
        case .hd1080: return 1
        case .uhd4k: return 2
        }
    }

    private func sessionPreset(for resolution: VideoResolution) -> AVCaptureSession.Preset {
        switch resolution {
        case .hd720: .hd1280x720
        case .hd1080: .hd1920x1080
        case .uhd4k: .hd4K3840x2160
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureVideoDataOutput {
            sampleDelegate?.didOutputVideoSampleBuffer(sampleBuffer)
            // Hand the same buffer to the police-detection subsystem; it
            // self-throttles and drops frames if still busy, so this is safe
            // to call on every video frame.
            PoliceDetectionSystem.shared.processFrame(sampleBuffer: sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            sampleDelegate?.didOutputAudioSampleBuffer(sampleBuffer)
        }
    }
}
