import Foundation

/// Subscription tier as exposed by the backend. Matches the Zod
/// `z.enum(['FREE', 'PRO', 'PREMIUM'])` and the Prisma enum of the same
/// shape — never introduce a new value here without touching both sides.
public enum APISubscriptionTier: String, Codable, Sendable, Hashable, CaseIterable {
    case free    = "FREE"
    case pro     = "PRO"
    case premium = "PREMIUM"

    public var displayName: String {
        switch self {
        case .free:    return "Free"
        case .pro:     return "Pro"
        case .premium: return "Premium"
        }
    }

    /// Strict ordering — `premium > pro > free`. Useful for gating UI.
    public var rank: Int {
        switch self {
        case .free:    return 0
        case .pro:     return 1
        case .premium: return 2
        }
    }

    /// Does this tier entitle access to features at `min` or above?
    public func meets(_ min: APISubscriptionTier) -> Bool {
        rank >= min.rank
    }
}

/// Subscription life-cycle status reported by the backend. Mirrors the
/// `subscription_status` Postgres enum.
public enum APISubscriptionStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case active           = "ACTIVE"
    case inGracePeriod    = "IN_GRACE_PERIOD"
    case inBillingRetry   = "IN_BILLING_RETRY"
    case expired          = "EXPIRED"
    case revoked          = "REVOKED"
    case paused           = "PAUSED"
}
