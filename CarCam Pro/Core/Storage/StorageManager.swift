import Foundation
import SwiftData
import OSLog

final class StorageManager: StorageManagerProtocol, @unchecked Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Usage Calculation

    func calculateTotalUsage() async -> Int64 {
        let recordingsURL = FileSystemManager.recordingsBaseURL
        let thumbnailsURL = FileSystemManager.thumbnailsBaseURL

        var totalSize: Int64 = 0

        for baseURL in [recordingsURL, thumbnailsURL] {
            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                      let fileSize = resourceValues.fileSize else { continue }
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    // MARK: - Cap Enforcement

    func enforceStorageCap() async throws {
        let cap = AppSettings.shared.storageCap
        let currentUsage = await calculateTotalUsage()

        guard currentUsage > cap else { return }

        let bytesToFree = currentUsage - cap
        var freedBytes: Int64 = 0

        let context = ModelContext(modelContainer)

        // Fetch all clips sorted by date (oldest first), excluding protected and starred
        let descriptor = FetchDescriptor<VideoClip>(
            predicate: #Predicate<VideoClip> { clip in
                clip.isProtected == false && clip.isStarred == false
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )

        guard let candidates = try? context.fetch(descriptor) else { return }

        for clip in candidates {
            guard freedBytes < bytesToFree else { break }

            let clipSize = clip.fileSize

            do {
                try await deleteClip(clip, context: context)
                freedBytes += clipSize
                AppLogger.storage.info("FIFO deleted: \(clip.fileName) (\(clip.formattedFileSize))")
            } catch {
                AppLogger.storage.error("Failed to delete clip \(clip.fileName): \(error.localizedDescription)")
            }
        }

        try? context.save()

        if freedBytes < bytesToFree {
            AppLogger.storage.warning("Storage still over cap after FIFO — remaining clips are protected")
        }

        AppLogger.storage.info("Storage enforcement: freed \(freedBytes) bytes, cap: \(cap)")
    }

    // MARK: - Deletion

    func deleteClip(_ clip: VideoClip, context: ModelContext) async throws {
        // Delete video file
        let fileURL = clip.fileURL
        try? FileSystemManager.deleteFile(at: fileURL)

        // Delete thumbnail
        if let thumbURL = clip.thumbnailURL {
            try? FileSystemManager.deleteFile(at: thumbURL)
        }

        // Delete SwiftData record
        context.delete(clip)
    }

    func deleteAllUnprotected(context: ModelContext) async throws {
        let descriptor = FetchDescriptor<VideoClip>(
            predicate: #Predicate<VideoClip> { clip in
                clip.isProtected == false && clip.isStarred == false
            }
        )

        guard let clips = try? context.fetch(descriptor) else { return }

        for clip in clips {
            try await deleteClip(clip, context: context)
        }

        try context.save()
        AppLogger.storage.info("Deleted all unprotected clips (\(clips.count) total)")
    }

    // MARK: - Protection

    /// Mark the newest clip of the given session as protected. Called from
    /// the live-HUD `LOCK` button and in response to incident events.
    func protectLatestClip(in sessionID: UUID, reason: ProtectionReason) async {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<VideoClip>(
            predicate: #Predicate<VideoClip> { clip in
                clip.session?.id == sessionID
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else { return }

        latest.isProtected = true
        latest.protectionReason = reason
        do {
            try context.save()
            AppLogger.storage.info("Protected clip \(latest.fileName) (\(reason.rawValue))")
        } catch {
            AppLogger.storage.error("Failed to persist protection: \(error.localizedDescription)")
        }
    }

    // MARK: - Device Space

    func availableDeviceSpace() -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: URL.documentsDirectory.path
        ),
              let freeSpace = attributes[.systemFreeSize] as? Int64 else {
            return 0
        }
        return freeSpace
    }

    // MARK: - Cleanup

    func cleanupOrphanedFiles() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<VideoClip>()
        let knownPaths: Set<String>

        if let clips = try? context.fetch(descriptor) {
            knownPaths = Set(clips.map(\.filePath))
        } else {
            knownPaths = []
        }

        let recordingsURL = FileSystemManager.recordingsBaseURL
        guard let enumerator = FileManager.default.enumerator(
            at: recordingsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var orphanedCount = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "mp4" else { continue }

            let relativePath = fileURL.path.replacingOccurrences(
                of: URL.documentsDirectory.path + "/",
                with: ""
            )

            if !knownPaths.contains(relativePath) {
                try? FileManager.default.removeItem(at: fileURL)
                orphanedCount += 1
            }
        }

        if orphanedCount > 0 {
            AppLogger.storage.info("Cleaned up \(orphanedCount) orphaned files")
        }
    }

    func cleanupOrphanedMetadata() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<VideoClip>()

        guard let clips = try? context.fetch(descriptor) else { return }

        var orphanedCount = 0
        for clip in clips {
            if !FileManager.default.fileExists(atPath: clip.fileURL.path) {
                context.delete(clip)
                orphanedCount += 1
            }
        }

        if orphanedCount > 0 {
            try? context.save()
            AppLogger.storage.info("Cleaned up \(orphanedCount) orphaned metadata records")
        }
    }
}
