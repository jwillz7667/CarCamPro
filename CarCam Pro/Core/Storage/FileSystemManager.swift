import Foundation
import OSLog

enum FileSystemManager {
    static let recordingsBaseURL: URL = {
        URL.documentsDirectory.appendingPathComponent(AppConstants.recordingsDirectoryName)
    }()

    static let thumbnailsBaseURL: URL = {
        URL.documentsDirectory.appendingPathComponent(AppConstants.thumbnailsDirectoryName)
    }()

    static let tempBaseURL: URL = {
        URL.documentsDirectory.appendingPathComponent(AppConstants.tempDirectoryName)
    }()

    static func ensureBaseDirectoriesExist() {
        let directories = [recordingsBaseURL, thumbnailsBaseURL, tempBaseURL]
        for dir in directories {
            createDirectoryIfNeeded(dir)
        }
    }

    static func sessionDirectory(date: Date, sessionID: UUID) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        let sessionShort = String(sessionID.uuidString.prefix(8)).lowercased()

        let url = recordingsBaseURL
            .appendingPathComponent(dateString)
            .appendingPathComponent("session_\(sessionShort)")

        createDirectoryIfNeeded(url)
        return url
    }

    static func clipFileName(sessionShortID: String, sequence: Int, timestamp: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestampString = dateFormatter.string(from: timestamp)
        return "clip_\(sessionShortID)_\(String(format: "%03d", sequence))_\(timestampString).mp4"
    }

    static func thumbnailFileName(clipID: UUID) -> String {
        "thumb_\(clipID.uuidString.prefix(8).lowercased()).jpg"
    }

    static func createDirectoryIfNeeded(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            AppLogger.storage.error("Failed to create directory at \(url.path): \(error.localizedDescription)")
        }
    }

    static func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    static func deleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
