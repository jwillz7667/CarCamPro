import Foundation

/// User profile as returned by `GET /v1/users/me` and friends.
/// `storageQuotaBytes` is emitted as a JSON string because Postgres BigInt
/// values exceed the safe integer range in JavaScript — we treat it as a
/// string on the wire and parse to `UInt64` locally.
public struct APIUser: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let locale: String?
    public let timezone: String?
    public let subscriptionTier: APISubscriptionTier
    public let storageQuotaBytes: String
    public let createdAt: Date

    public var storageQuota: UInt64 {
        UInt64(storageQuotaBytes) ?? 0
    }
}

/// Minimal user shape as returned by `POST /v1/auth/apple` (login response).
public struct APIAuthUser: Codable, Sendable, Equatable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let subscriptionTier: APISubscriptionTier
}
