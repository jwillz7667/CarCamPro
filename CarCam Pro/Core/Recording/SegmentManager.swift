import AVFoundation
import SwiftData
import UIKit
import OSLog

final class SegmentManager: @unchecked Sendable {
    // `rotationLock` guards every field below up to and including
    // `currentSegmentIndex`. The camera delegate calls `processSampleBuffer`
    // on `cameraQueue` while `stopCurrentSegment` is invoked from the main
    // actor and `rotateSegment` spawns a `Task.detached` finalizer — so
    // rotation state must be pinned with a mutex rather than relying on
    // the camera queue alone.
    private let rotationLock = NSLock()
    private var currentProxy: WriterProxy?
    private var nextProxy: WriterProxy?
    private var segmentStartTime: CMTime?
    /// Wall-clock timestamp captured the moment `segmentStartTime` is
    /// first assigned. Lets us produce accurate `VideoClip.startDate`
    /// values that align with the PTS boundary rather than the
    /// finalize-completion time.
    private var segmentStartWallClock: Date?
    private var isPreWarming = false
    private var isRotating = false

    private(set) var currentSegmentIndex: Int = 0

    private let segmentDuration: TimeInterval
    private let sessionShortID: String
    private let sessionDirectory: URL
    private let modelContainer: ModelContainer?
    private let sessionID: UUID
    private let audioEnabled: Bool

    nonisolated(unsafe) var onSegmentCompleted: (@Sendable (Int) -> Void)?
    /// Invoked when a writer reports a terminal failure. The engine treats
    /// this as a recording-fatal event and stops the session.
    nonisolated(unsafe) var onWriterFailure: (@Sendable (Error) -> Void)?

    init(
        segmentDuration: TimeInterval,
        sessionShortID: String,
        sessionDirectory: URL,
        modelContainer: ModelContainer?,
        sessionID: UUID,
        audioEnabled: Bool
    ) {
        self.segmentDuration = segmentDuration
        self.sessionShortID = sessionShortID
        self.sessionDirectory = sessionDirectory
        self.modelContainer = modelContainer
        self.sessionID = sessionID
        self.audioEnabled = audioEnabled
    }

    // MARK: - Start / Stop

    func startFirstSegment() throws -> WriterProxy {
        let proxy = try createWriterProxy(segmentIndex: 1)
        rotationLock.lock()
        currentSegmentIndex = 1
        currentProxy = proxy
        segmentStartTime = nil
        segmentStartWallClock = nil
        rotationLock.unlock()
        return proxy
    }

    func stopCurrentSegment() async throws -> URL? {
        // Snapshot the state we need under the lock, then release it
        // before hitting `await` so we don't hold a mutex across a
        // suspension point.
        rotationLock.lock()
        let proxy = currentProxy
        let index = currentSegmentIndex
        let startWall = segmentStartWallClock
        currentProxy = nil
        nextProxy = nil
        segmentStartTime = nil
        segmentStartWallClock = nil
        rotationLock.unlock()

        guard let proxy else { return nil }
        let url = try await proxy.writer.finish()
        await saveClipMetadata(
            fileURL: url,
            segmentIndex: index,
            startWallClock: startWall ?? Date().addingTimeInterval(-segmentDuration)
        )
        return url
    }

    // MARK: - Sample Buffer Processing

    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Capture the proxy we will write into plus enough state to decide
        // whether to trigger a pre-warm or rotation — all under one lock,
        // so a concurrent stop/rotation can't tear it.
        rotationLock.lock()
        let proxy = currentProxy
        if segmentStartTime == nil {
            segmentStartTime = timestamp
            segmentStartWallClock = Date()
        }
        let startTime = segmentStartTime
        let shouldPreWarm: Bool = {
            guard let start = startTime else { return false }
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, start))
            return elapsed >= segmentDuration - AppConstants.preWarmLeadTime
                && !isPreWarming
                && nextProxy == nil
        }()
        let shouldRotate: Bool = {
            guard let start = startTime else { return false }
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, start))
            return elapsed >= segmentDuration && !isRotating
        }()
        if shouldPreWarm { isPreWarming = true }
        if shouldRotate { isRotating = true }
        rotationLock.unlock()

        guard let proxy else { return }

        if shouldPreWarm { preWarmNextSegment() }
        if shouldRotate { rotateSegment(atTime: timestamp) }

        // Write to current segment.
        if isVideo {
            proxy.handleVideoSampleBuffer(sampleBuffer)
        } else {
            proxy.handleAudioSampleBuffer(sampleBuffer)
        }
    }

    // MARK: - Private

    private func preWarmNextSegment() {
        rotationLock.lock()
        let nextIndex = currentSegmentIndex + 1
        rotationLock.unlock()

        // `createWriterProxy` creates + configures an AVAssetWriter which
        // does real file-system I/O. Perform it outside the rotation lock.
        let newProxy: WriterProxy?
        do {
            newProxy = try createWriterProxy(segmentIndex: nextIndex)
            AppLogger.recording.debug("Pre-warmed segment \(nextIndex)")
        } catch {
            AppLogger.recording.error("Failed to pre-warm next segment: \(error.localizedDescription)")
            newProxy = nil
        }

        rotationLock.lock()
        nextProxy = newProxy
        isPreWarming = false
        rotationLock.unlock()
    }

    private func rotateSegment(atTime timestamp: CMTime) {
        rotationLock.lock()
        let previousProxy = currentProxy
        let previousIndex = currentSegmentIndex
        let previousStartWall = segmentStartWallClock
        var newProxy = nextProxy
        nextProxy = nil
        rotationLock.unlock()

        // If the pre-warm didn't complete in time, synchronously create the
        // next writer now. This can block the camera queue briefly — rare
        // path; the pre-warm lead is tuned so we typically avoid it.
        if newProxy == nil {
            do {
                newProxy = try createWriterProxy(segmentIndex: previousIndex + 1)
            } catch {
                AppLogger.recording.error("Failed to create writer during rotation: \(error.localizedDescription)")
                rotationLock.lock()
                isRotating = false
                rotationLock.unlock()
                onWriterFailure?(error)
                return
            }
        }

        rotationLock.lock()
        currentProxy = newProxy
        currentSegmentIndex = previousIndex + 1
        segmentStartTime = timestamp
        segmentStartWallClock = Date()
        isRotating = false
        let newIndex = currentSegmentIndex
        rotationLock.unlock()

        AppLogger.recording.info("Segment rotated: \(previousIndex) → \(newIndex)")

        // Finalize previous writer in background.
        if let previousProxy {
            let segmentIdx = previousIndex
            let logger = AppLogger.recording
            let wallClock = previousStartWall ?? Date().addingTimeInterval(-segmentDuration)
            Task.detached { [weak self] in
                do {
                    let url = try await previousProxy.writer.finish()
                    await self?.saveClipMetadata(
                        fileURL: url,
                        segmentIndex: segmentIdx,
                        startWallClock: wallClock
                    )
                    self?.onSegmentCompleted?(segmentIdx)
                } catch {
                    logger.error("Failed to finalize segment \(segmentIdx): \(error.localizedDescription)")
                    self?.onWriterFailure?(error)
                }
            }
        }
    }

    private func createWriterProxy(segmentIndex: Int) throws -> WriterProxy {
        let fileName = FileSystemManager.clipFileName(
            sessionShortID: sessionShortID,
            sequence: segmentIndex,
            timestamp: Date()
        )
        let outputURL = sessionDirectory.appendingPathComponent(fileName)
        let settings = AppSettings.shared

        let writer = VideoWriter(outputURL: outputURL)
        try writer.setup(
            resolution: settings.resolution,
            frameRate: settings.frameRate,
            codec: settings.codec,
            audioEnabled: audioEnabled
        )
        // Bubble terminal writer failures up to the engine via
        // `onWriterFailure`. Captured weakly so a segment being torn down
        // during a stop doesn't pin the manager.
        writer.onFailure = { [weak self] error in
            self?.onWriterFailure?(error)
        }

        return WriterProxy(writer: writer)
    }

    private func saveClipMetadata(
        fileURL: URL,
        segmentIndex: Int,
        startWallClock: Date
    ) async {
        guard let modelContainer else { return }

        let relativePath = fileURL.path.replacingOccurrences(
            of: URL.documentsDirectory.path + "/",
            with: ""
        )

        let fileSize = FileSystemManager.fileSize(at: fileURL)
        let settings = AppSettings.shared

        // Real duration = now − start, but never more than the target
        // segment duration (stop-in-the-middle clips use the actual
        // elapsed time). A short final segment is valid.
        let elapsed = Date().timeIntervalSince(startWallClock)
        let duration = min(max(elapsed, 0), segmentDuration)

        let clip = VideoClip(
            fileName: fileURL.lastPathComponent,
            filePath: relativePath,
            startDate: startWallClock,
            duration: duration,
            fileSize: fileSize,
            resolution: settings.resolution,
            frameRate: settings.frameRate,
            codec: settings.codec
        )
        clip.endDate = startWallClock.addingTimeInterval(duration)

        // Generate thumbnail
        await generateThumbnail(for: fileURL, clip: clip)

        // Link to session and save
        let context = ModelContext(modelContainer)
        let targetSessionID = sessionID
        let sessionDescriptor = FetchDescriptor<RecordingSession>(
            predicate: #Predicate { $0.id == targetSessionID }
        )
        if let session = try? context.fetch(sessionDescriptor).first {
            clip.session = session
            session.totalSegments = segmentIndex
        }
        context.insert(clip)
        try? context.save()

        AppLogger.recording.info("Segment \(segmentIndex) saved: \(clip.fileName), \(clip.formattedFileSize)")
    }

    private func generateThumbnail(for videoURL: URL, clip: VideoClip) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)

        let time = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: time)
            let uiImage = UIImage(cgImage: cgImage)
            guard let data = uiImage.jpegData(compressionQuality: 0.7) else { return }

            let thumbFileName = FileSystemManager.thumbnailFileName(clipID: clip.id)
            let thumbURL = FileSystemManager.thumbnailsBaseURL.appendingPathComponent(thumbFileName)
            try data.write(to: thumbURL)

            let relativePath = thumbURL.path.replacingOccurrences(
                of: URL.documentsDirectory.path + "/",
                with: ""
            )
            clip.thumbnailPath = relativePath
        } catch {
            AppLogger.recording.debug("Thumbnail generation failed for segment: \(error.localizedDescription)")
        }
    }
}
