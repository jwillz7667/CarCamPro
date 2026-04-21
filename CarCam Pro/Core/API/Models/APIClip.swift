import Foundation

/// Upload lifecycle state. Mirrors Postgres `upload_status` enum.
public enum APIUploadStatus: String, Codable, Sendable, Hashable {
    case pending   = "PENDING"
    case uploading = "UPLOADING"
    case uploaded  = "UPLOADED"
    case failed    = "FAILED"
    case purged    = "PURGED"
}

/// Clip severity label. Server values are `minor | moderate | severe`;
/// kept as a string here so unknown values don't fail decoding.
public struct APIClip: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// Backend emits BigInt as a string — parse to `UInt64` locally.
    public let sizeBytes: String
    public let durationSeconds: Double
    public let resolution: String
    public let frameRate: Int
    public let codec: String
    public let startedAt: Date
    public let endedAt: Date
    public let isProtected: Bool
    public let hasIncident: Bool
    public let incidentSeverity: String?
    public let peakGForce: Double?
    public let uploadStatus: APIUploadStatus
    public let uploadedAt: Date?
    public let createdAt: Date

    public var sizeInBytes: UInt64 { UInt64(sizeBytes) ?? 0 }
}

/// Cursor-paginated clip list from `GET /v1/clips`.
public struct APIClipListResponse: Codable, Sendable, Equatable {
    public let clips: [APIClip]
    public let nextCursor: String?
}

/// Body for `POST /v1/clips/init`. `sizeBytes` is emitted as a string
/// for the same BigInt-safety reason as the response.
public struct APIInitClipPayload: Codable, Sendable, Equatable {
    public let deviceId: String
    public let sizeBytes: String
    public let contentType: String
    public let sha256Base64: String

    public init(deviceId: String, sizeBytes: UInt64, contentType: String = "video/mp4", sha256Base64: String) {
        self.deviceId = deviceId
        self.sizeBytes = String(sizeBytes)
        self.contentType = contentType
        self.sha256Base64 = sha256Base64
    }
}

/// Response from `POST /v1/clips/init`.
public struct APIInitClipResponse: Codable, Sendable, Equatable {
    public let clipId: String
    public let uploadUrl: URL
    public let storageKey: String
    public let expiresInSeconds: Int
}

/// Body for `POST /v1/clips/:id/complete`.
public struct APICompleteClipPayload: Codable, Sendable {
    public let durationSeconds: Double
    public let resolution: String
    public let frameRate: Int
    public let codec: String
    public let startedAt: Date
    public let endedAt: Date
    public let isProtected: Bool
    public let protectionReason: String?
    public let hasIncident: Bool
    public let incidentSeverity: String?
    public let peakGForce: Double?
    public let incidentTimestamp: Date?
    public let startLatitude: Double?
    public let startLongitude: Double?
    public let endLatitude: Double?
    public let endLongitude: Double?
    public let averageSpeedMPH: Double?

    public init(
        durationSeconds: Double,
        resolution: String,
        frameRate: Int,
        codec: String,
        startedAt: Date,
        endedAt: Date,
        isProtected: Bool,
        protectionReason: String? = nil,
        hasIncident: Bool,
        incidentSeverity: String? = nil,
        peakGForce: Double? = nil,
        incidentTimestamp: Date? = nil,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        averageSpeedMPH: Double? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isProtected = isProtected
        self.protectionReason = protectionReason
        self.hasIncident = hasIncident
        self.incidentSeverity = incidentSeverity
        self.peakGForce = peakGForce
        self.incidentTimestamp = incidentTimestamp
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.averageSpeedMPH = averageSpeedMPH
    }
}

/// Response from `GET /v1/clips/:id/download`.
public struct APIDownloadURLResponse: Codable, Sendable, Equatable {
    public let url: URL
    public let expiresInSeconds: Int
}
