import AVFoundation
import OSLog

final class VideoWriter: @unchecked Sendable {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let outputURL: URL

    private(set) var isWriting = false
    private var hasStartedSession = false

    /// Sticky failure flag — set the first time we observe `assetWriter
    /// .status == .failed` during an append. Subsequent appends short-circuit
    /// immediately instead of re-invoking the (failed) AVFoundation call.
    private var hasFailed = false

    /// Invoked exactly once when the writer transitions into a terminal
    /// failure state. `SegmentManager` forwards this up to `RecordingEngine`
    /// which stops the session and surfaces the error in the UI.
    nonisolated(unsafe) var onFailure: (@Sendable (Error) -> Void)?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    // MARK: - Setup

    func setup(resolution: VideoResolution, frameRate: Int, codec: VideoCodec, audioEnabled: Bool) throws {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video input
        let dimensions = resolution.dimensions
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec.avCodecType,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: resolution.bitrate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                AVVideoAllowFrameReorderingKey: true,
            ] as [String: Any]
        ]

        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput.expectsMediaDataInRealTime = true
        videoWriterInput.transform = CGAffineTransform(rotationAngle: .pi / 2)

        guard writer.canAdd(videoWriterInput) else {
            throw VideoWriterError.setupFailed("Cannot add video input to asset writer")
        }
        writer.add(videoWriterInput)

        // Audio input
        if audioEnabled {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 64_000,
            ]

            let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioWriterInput.expectsMediaDataInRealTime = true

            if writer.canAdd(audioWriterInput) {
                writer.add(audioWriterInput)
                audioInput = audioWriterInput
            }
        }

        assetWriter = writer
        videoInput = videoWriterInput

        AppLogger.recording.info("VideoWriter setup: \(resolution.rawValue) @ \(frameRate)fps, codec: \(codec.rawValue)")
    }

    // MARK: - Writing

    func start(atSourceTime sourceTime: CMTime) throws {
        guard let assetWriter else {
            throw VideoWriterError.invalidState("Asset writer not set up")
        }

        guard assetWriter.startWriting() else {
            let errorDesc = assetWriter.error?.localizedDescription ?? "Unknown error"
            throw VideoWriterError.setupFailed("Failed to start writing: \(errorDesc)")
        }

        assetWriter.startSession(atSourceTime: sourceTime)
        hasStartedSession = true
        isWriting = true
    }

    func appendVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting, hasStartedSession, !hasFailed,
              let videoInput,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        let ok = videoInput.append(sampleBuffer)
        if !ok { handleAppendFailure(channel: "video") }
    }

    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting, hasStartedSession, !hasFailed,
              let audioInput,
              audioInput.isReadyForMoreMediaData else {
            return
        }
        let ok = audioInput.append(sampleBuffer)
        if !ok { handleAppendFailure(channel: "audio") }
    }

    /// Called when `AVAssetWriterInput.append` returns `false` — the writer
    /// is in `.failed` state and will never accept another buffer. We flip
    /// the sticky `hasFailed` flag, log the AVError, and fire the
    /// `onFailure` callback exactly once so the engine can tear down.
    private func handleAppendFailure(channel: String) {
        guard !hasFailed else { return }
        hasFailed = true
        isWriting = false
        let error = assetWriter?.error
            ?? VideoWriterError.finishFailed("\(channel) append failed (no error detail)")
        AppLogger.recording.error(
            "VideoWriter \(channel) append failed (status=\(self.assetWriter?.status.rawValue ?? -1)): \(error.localizedDescription)"
        )
        // Best-effort: remove the partial file so the FIFO cap doesn't
        // account for a 0-byte clip that can't be played back.
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        onFailure?(error)
    }

    func finish() async throws -> URL {
        guard let assetWriter else {
            throw VideoWriterError.invalidState("Asset writer not set up")
        }

        isWriting = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        return try await withCheckedThrowingContinuation { continuation in
            assetWriter.finishWriting {
                if assetWriter.status == .completed {
                    AppLogger.recording.info("VideoWriter finished: \(self.outputURL.lastPathComponent)")
                    continuation.resume(returning: self.outputURL)
                } else {
                    let errorDesc = assetWriter.error?.localizedDescription ?? "Unknown error"
                    continuation.resume(throwing: VideoWriterError.finishFailed(errorDesc))
                }
            }
        }
    }

    var writerOutputURL: URL { outputURL }
}
