import Foundation
import Observation
import OSLog

/// Process-wide source of truth for **what the current user is entitled to**.
///
/// Every feature-gated surface binds to `EntitlementStore.shared.tier` rather
/// than reaching into `APIClient.currentSubscription(...)` directly, for two
/// reasons:
///
///   1. **Fast.** UI reads are synchronous — no round-trip, no spinner.
///   2. **Reactive.** Because the store is `@Observable`, flipping to
///      `.premium` after a successful purchase re-renders every gate in
///      the app (paywall button, resolution picker, incident-report button)
///      without any plumbing on the UI side.
///
/// The store is authoritative at the app boundary: it reconciles
/// **server state** (`APIClient.currentSubscription()`) and **StoreKit
/// state** (the latest verified `Transaction`) and exposes the *max* of
/// the two. StoreKit is trusted for offline purchases; the server is
/// trusted for cross-device entitlement roaming (same Apple ID, different
/// phone — the server still has the active record).
///
/// Authentication state is mirrored here too so views can render a
/// "sign in to unlock" card when we have no bearer token.
@Observable
@MainActor
final class EntitlementStore {
    static let shared = EntitlementStore()

    /// User-facing tier. `FREE` when unauthenticated OR when no active
    /// paid subscription has been verified.
    private(set) var tier: APISubscriptionTier = .free
    /// Server-reported lifecycle status — `.active`, `.inGracePeriod`, etc.
    /// Nil when we've never successfully called `/v1/subscriptions/current`.
    private(set) var status: APISubscriptionStatus?
    /// When the current paid period ends. Nil for `FREE`.
    private(set) var currentPeriodEndsAt: Date?
    /// Whether auto-renew is on — used by the Settings subscription card.
    private(set) var autoRenew: Bool?
    /// The StoreKit product ID backing the current subscription, when known.
    /// Used to highlight the active card in the paywall.
    private(set) var activeProductId: String?

    /// Whether the user has signed in with Apple (has a bearer token).
    /// The SignInView flips this via `markSignedIn()` immediately after
    /// `APIClient.signInWithApple` returns, so the paywall + settings
    /// don't need to wait for the next `refresh()` to render correctly.
    private(set) var isSignedIn: Bool

    /// Whether the user has *ever* seen the paywall in this install. Set
    /// by `PaywallView` whether they purchase, skip, or restore — used to
    /// stop the onboarding flow from looping back into it.
    var hasSeenPaywall: Bool {
        get { UserDefaults.standard.bool(forKey: Self.paywallSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.paywallSeenKey) }
    }

    private static let paywallSeenKey = "entitlement.paywallSeen"

    // Dependency for the server refresh path. Default to the app-wide
    // APIClient shared through `DependencyContainer`; tests inject a fake.
    private var api: APIClientProtocol

    private init(api: APIClientProtocol = APIClient()) {
        self.api = api
        self.isSignedIn = api.isAuthenticated
    }

    /// Swap in a different API client. Used by `DependencyContainer` at
    /// boot so `.shared` talks to the same `APIClient` the rest of the app
    /// uses (and picks up any shared token store).
    func bind(api: APIClientProtocol) {
        self.api = api
        self.isSignedIn = api.isAuthenticated
    }

    // MARK: - Sign-in hooks

    func markSignedIn() {
        isSignedIn = true
    }

    func markSignedOut() {
        isSignedIn = false
        tier = .free
        status = nil
        currentPeriodEndsAt = nil
        autoRenew = nil
        activeProductId = nil
    }

    // MARK: - Entitlement mutation

    /// Apply a freshly-verified StoreKit transaction. Promotes the tier if
    /// the new product maps to a higher tier than what we already have.
    ///
    /// StoreKit is our *offline-friendly* source: if the user just bought
    /// premium while the server is unreachable, this lets the paywall
    /// dismiss + unlock 4K immediately. The next successful server refresh
    /// reconciles.
    func apply(productId: String, expiresAt: Date?) {
        let productTier = Self.tier(forProductId: productId)
        if productTier.rank >= tier.rank {
            tier = productTier
            status = .active
            currentPeriodEndsAt = expiresAt
            autoRenew = true
            activeProductId = productId
            AppLogger.ui.notice("EntitlementStore: applied \(productId) → tier=\(self.tier.rawValue)")
        }
    }

    /// Apply a server `GET /v1/subscriptions/current` response.
    ///
    /// The server is authoritative for the expiry/status side of things —
    /// it sees Apple's server-to-server notifications and knows about
    /// grace periods, refunds, etc. Trust it for downgrades. But if the
    /// client has a fresher StoreKit transaction that promotes the tier,
    /// we keep that: a just-purchased entitlement shouldn't be clobbered
    /// by a slightly-stale `/current` response.
    func apply(subscription: APISubscription) {
        let serverTier = subscription.tier
        if serverTier.rank >= tier.rank {
            tier = serverTier
        } else if status == nil {
            // First-ever load — trust the server.
            tier = serverTier
        }
        status = subscription.status
        currentPeriodEndsAt = subscription.currentPeriodEndsAt
        autoRenew = subscription.autoRenew
        activeProductId = subscription.productId
    }

    // MARK: - Server refresh

    /// Pull the latest subscription from the server. No-op when unauth'd.
    func refresh() async {
        guard api.isAuthenticated else { return }
        do {
            let current = try await api.currentSubscription()
            apply(subscription: current)
        } catch {
            AppLogger.ui.error("EntitlementStore.refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Product → Tier mapping

    /// Map a StoreKit product ID to a backend tier. Centralised so the
    /// paywall + entitlement store + any gating UI all agree on the
    /// mapping.
    static func tier(forProductId productId: String) -> APISubscriptionTier {
        let lowered = productId.lowercased()
        if lowered.contains("premium") { return .premium }
        if lowered.contains("pro") { return .pro }
        return .free
    }
}

// MARK: - Feature gates
//
// Centralise every "does this tier get to do X" decision so the feature
// site just asks `EntitlementStore.shared.canUseX` rather than hand-coding
// tier comparisons across the codebase.
extension EntitlementStore {
    /// 4K capture requires Premium; Pro gets 1080p; Free gets 720p.
    var maxResolution: VideoResolution {
        switch tier {
        case .free:    return .hd720
        case .pro:     return .hd1080
        case .premium: return .uhd4k
        }
    }

    /// Background recording is a paid feature.
    var canRecordInBackground: Bool { tier.meets(.pro) }

    /// Cloud backup + server-side incident reports are paid features.
    var canUseCloudBackup: Bool { tier.meets(.pro) }

    /// Premium-only: 60-second pre/post incident buffer (Free/Pro get 30s).
    var incidentBufferSeconds: TimeInterval { tier.meets(.premium) ? 60 : 30 }

    /// Premium gets unlimited local storage; Pro gets 10 GB; Free gets 2 GB.
    var storageCapBytes: Int64 {
        switch tier {
        case .free:    return 2 * 1024 * 1024 * 1024
        case .pro:     return 10 * 1024 * 1024 * 1024
        case .premium: return Int64.max
        }
    }
}
