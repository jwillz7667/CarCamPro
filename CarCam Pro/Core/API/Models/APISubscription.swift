import Foundation

/// Subscription record from `GET /v1/subscriptions/current`. When no active
/// subscription exists, fields are nullable and `tier = .free`.
public struct APISubscription: Codable, Sendable, Equatable {
    public let tier: APISubscriptionTier
    public let status: APISubscriptionStatus?
    public let productId: String?
    public let currentPeriodEndsAt: Date?
    public let autoRenew: Bool?
}

/// Body for `POST /v1/subscriptions/verify`.
public struct APISubscriptionVerifyPayload: Codable, Sendable {
    public let signedTransactionPayload: String
    public let signedRenewalInfoPayload: String?

    public init(signedTransactionPayload: String, signedRenewalInfoPayload: String? = nil) {
        self.signedTransactionPayload = signedTransactionPayload
        self.signedRenewalInfoPayload = signedRenewalInfoPayload
    }
}

/// Response from `POST /v1/subscriptions/verify`. Contains the
/// authoritative server-side state after verifying the StoreKit JWS.
public struct APISubscriptionVerifyResponse: Codable, Sendable, Equatable {
    public let tier: APISubscriptionTier
    public let status: APISubscriptionStatus
    public let currentPeriodEndsAt: Date
    public let autoRenew: Bool
}
