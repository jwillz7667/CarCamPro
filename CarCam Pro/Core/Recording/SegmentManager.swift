import AVFoundation
import SwiftData
import UIKit
import OSLog

final class SegmentManager: @unchecked Sendable {
    private var currentProxy: WriterProxy?
    private var nextProxy: WriterProxy?
    private var segmentStartTime: CMTime?
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
        currentSegmentIndex = 1
        let proxy = try createWriterProxy(segmentIndex: 1)
        currentProxy = proxy
        return proxy
    }

    func stopCurrentSegment() async throws -> URL? {
        guard let proxy = currentProxy else { return nil }

        currentProxy = nil
        nextProxy = nil

        let url = try await proxy.writer.finish()
        await saveClipMetadata(fileURL: url, segmentIndex: currentSegmentIndex)
        return url
    }

    // MARK: - Sample Buffer Processing

    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        guard let proxy = currentProxy else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Initialize segment start time on first buffer
        if segmentStartTime == nil {
            segmentStartTime = timestamp
        }

        // Check elapsed time
        if let startTime = segmentStartTime {
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, startTime))

            // Pre-warm next writer 2 seconds before rotation
            if elapsed >= segmentDuration - AppConstants.preWarmLeadTime && !isPreWarming && nextProxy == nil {
                preWarmNextSegment()
            }

            // Rotate at segment boundary
            if elapsed >= segmentDuration && !isRotating {
                rotateSegment(atTime: timestamp)
            }
        }

        // Write to current segment
        if isVideo {
            proxy.handleVideoSampleBuffer(sampleBuffer)
        } else {
            proxy.handleAudioSampleBuffer(sampleBuffer)
        }
    }

    // MARK: - Private

    private func preWarmNextSegment() {
        isPreWarming = true

        do {
            let nextIndex = currentSegmentIndex + 1
            let proxy = try createWriterProxy(segmentIndex: nextIndex)
            nextProxy = proxy
            AppLogger.recording.debug("Pre-warmed segment \(nextIndex)")
        } catch {
            AppLogger.recording.error("Failed to pre-warm next segment: \(error.localizedDescription)")
        }

        isPreWarming = false
    }

    private func rotateSegment(atTime timestamp: CMTime) {
        isRotating = true

        let previousProxy = currentProxy
        let previousIndex = currentSegmentIndex

        // Swap to next writer
        if let next = nextProxy {
            currentProxy = next
            nextProxy = nil
        } else {
            // If pre-warming didn't complete, create writer now
            do {
                let proxy = try createWriterProxy(segmentIndex: currentSegmentIndex + 1)
                currentProxy = proxy
            } catch {
                AppLogger.recording.error("Failed to create writer during rotation: \(error.localizedDescription)")
                isRotating = false
                return
            }
        }

        currentSegmentIndex += 1
        segmentStartTime = timestamp

        AppLogger.recording.info("Segment rotated: \(previousIndex) → \(self.currentSegmentIndex)")

        // Finalize previous writer in background
        if let previousProxy {
            let segmentIdx = previousIndex
            let logger = AppLogger.recording
            Task.detached { [weak self] in
                do {
                    let url = try await previousProxy.writer.finish()
                    await self?.saveClipMetadata(fileURL: url, segmentIndex: segmentIdx)
                    self?.onSegmentCompleted?(segmentIdx)
                } catch {
                    logger.error("Failed to finalize segment \(segmentIdx): \(error.localizedDescription)")
                }
            }
        }

        isRotating = false
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

        return WriterProxy(writer: writer)
    }

    private func saveClipMetadata(fileURL: URL, segmentIndex: Int) async {
        guard let modelContainer else { return }

        let relativePath = fileURL.path.replacingOccurrences(
            of: URL.documentsDirectory.path + "/",
            with: ""
        )

        let fileSize = FileSystemManager.fileSize(at: fileURL)
        let settings = AppSettings.shared

        let clip = VideoClip(
            fileName: fileURL.lastPathComponent,
            filePath: relativePath,
            startDate: Date().addingTimeInterval(-segmentDuration),
            duration: segmentDuration,
            fileSize: fileSize,
            resolution: settings.resolution,
            frameRate: settings.frameRate,
            codec: settings.codec
        )
        clip.endDate = Date()

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
