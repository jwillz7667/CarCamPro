import Foundation
import SwiftData

@Model
final class VideoClip {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var filePath: String
    var thumbnailPath: String?
    var startDate: Date
    var endDate: Date?
    var duration: TimeInterval
    var fileSize: Int64

    // Stored as raw values for SwiftData compatibility
    var resolutionRawValue: String
    var frameRate: Int
    var codecRawValue: String

    // Protection
    var isProtected: Bool
    var isStarred: Bool
    var protectionReasonRawValue: String?

    // Incident
    var hasIncident: Bool
    var incidentTimestamp: Date?
    var incidentSeverityRawValue: String?
    var peakGForce: Double?

    // Location
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var averageSpeed: Double?

    // Relationship
    var session: RecordingSession?

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        startDate: Date = Date(),
        duration: TimeInterval = 0,
        fileSize: Int64 = 0,
        resolution: VideoResolution = .hd1080,
        frameRate: Int = 30,
        codec: VideoCodec = .hevc
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.startDate = startDate
        self.duration = duration
        self.fileSize = fileSize
        self.resolutionRawValue = resolution.rawValue
        self.frameRate = frameRate
        self.codecRawValue = codec.rawValue
        self.isProtected = false
        self.isStarred = false
        self.hasIncident = false
    }

    // MARK: - Typed Accessors

    var resolution: VideoResolution {
        get { VideoResolution(rawValue: resolutionRawValue) ?? .hd1080 }
        set { resolutionRawValue = newValue.rawValue }
    }

    var codec: VideoCodec {
        get { VideoCodec(rawValue: codecRawValue) ?? .hevc }
        set { codecRawValue = newValue.rawValue }
    }

    var protectionReason: ProtectionReason? {
        get { protectionReasonRawValue.flatMap { ProtectionReason(rawValue: $0) } }
        set { protectionReasonRawValue = newValue?.rawValue }
    }

    var incidentSeverity: IncidentSeverity? {
        get { incidentSeverityRawValue.flatMap { IncidentSeverity(rawValue: $0) } }
        set { incidentSeverityRawValue = newValue?.rawValue }
    }

    var fileURL: URL {
        URL.documentsDirectory.appendingPathComponent(filePath)
    }

    var thumbnailURL: URL? {
        thumbnailPath.map { URL.documentsDirectory.appendingPathComponent($0) }
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}
