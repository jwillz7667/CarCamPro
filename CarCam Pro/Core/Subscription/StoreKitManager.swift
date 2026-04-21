import Foundation
import StoreKit
import Observation
import OSLog

/// Process-wide StoreKit 2 coordinator.
///
/// Responsibilities:
///   • Fetch `Product` objects for the three CarCam Pro subscriptions.
///   • Execute purchases with optional promotional/intro offers, verifying
///     the returned JWS signature via StoreKit's `VerificationResult`.
///   • Listen to `Transaction.updates` for the lifetime of the process so
///     renewals, family-sharing changes, and refunds all land in
///     `EntitlementStore` without a user-initiated action.
///   • Post verified transactions to the backend via
///     `APIClient.verifySubscription(...)` so the server-side view of the
///     customer stays consistent with StoreKit.
///
/// **Note on product IDs.** CarCam Pro ships three subscription products
/// (Free is identity-only, not a product). The identifiers MUST match App
/// Store Connect *and* the `.storekit` configuration file one-for-one:
///
///   • `pro.carcam.pro.monthly`     — $4.99 / mo, 7-day free trial
///   • `pro.carcam.pro.yearly`      — $49.99 / yr, 7-day free trial
///   • `pro.carcam.premium.monthly` — $9.99 / mo, 7-day free trial
///   • `pro.carcam.premium.yearly`  — $99.99 / yr, 7-day free trial
///
/// Listing the set here centralises the contract.
@MainActor
@Observable
final class StoreKitManager {
    static let shared = StoreKitManager()

    /// Product IDs CarCam Pro ships. Order matters for the paywall — the
    /// higher-value monthly appears *before* yearly within a tier so the
    /// default highlight lands on monthly-premium.
    static let productIds: Set<String> = [
        "pro.carcam.pro.monthly",
        "pro.carcam.pro.yearly",
        "pro.carcam.premium.monthly",
        "pro.carcam.premium.yearly",
    ]

    /// Canonical display order. The paywall renders tiers in this order.
    static let displayOrder: [String] = [
        "pro.carcam.pro.monthly",
        "pro.carcam.pro.yearly",
        "pro.carcam.premium.monthly",
        "pro.carcam.premium.yearly",
    ]

    /// Loaded StoreKit products keyed by product ID. Empty until `load()`
    /// has finished; bindings against this should render a loading state.
    private(set) var products: [String: Product] = [:]
    /// True while a `load()` or purchase is in flight — the paywall
    /// disables tapping during these windows.
    private(set) var isWorking: Bool = false
    /// Last user-facing error message from a purchase or verification.
    private(set) var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?
    // APIClientProtocol isn't AnyObject-bound so we can't hold it weakly.
    // `StoreKitManager` is a process-wide singleton and `APIClient` likewise,
    // so a strong reference here is a no-op on lifetime.
    private var apiClient: APIClientProtocol?

    private init() {}

    /// Call once at app boot so `Transaction.updates` starts pumping and
    /// any backgrounded renewal/refund gets captured. Also registers the
    /// APIClient used to sync verified transactions to the backend.
    func bootstrap(api: APIClientProtocol) {
        apiClient = api
        startTransactionListener()
    }

    /// Load product metadata from the App Store. Idempotent — calling
    /// twice just refreshes the map.
    func load() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let fetched = try await Product.products(for: Self.productIds)
            var map: [String: Product] = [:]
            for p in fetched { map[p.id] = p }
            products = map
            AppLogger.ui.info("StoreKit loaded \(fetched.count) products")
        } catch {
            lastErrorMessage = "Couldn't load subscription options. \(error.localizedDescription)"
            AppLogger.ui.error("StoreKit product fetch failed: \(error.localizedDescription)")
        }
    }

    /// Outcome of a `purchase(_:)` call that the paywall renders on.
    enum PurchaseOutcome {
        /// Transaction verified and applied to the EntitlementStore.
        case success(productId: String, expiresAt: Date?)
        /// User cancelled the StoreKit sheet — not an error, don't surface one.
        case userCancelled
        /// Purchase is pending (SCA / Ask-to-Buy) — sheet already informed the user.
        case pending
        /// Apple returned an unverified JWS; we reject it as if cancelled
        /// but log loudly so QA can notice.
        case verificationFailed
        /// Apple or our backend rejected the transaction. `message` is
        /// user-facing-safe (StoreKit's localized description).
        case error(message: String)
    }

    /// Execute a purchase for the given product. Handles:
    ///   • JWS verification via `VerificationResult`.
    ///   • Server-side verification to keep the backend subscription
    ///     record in sync (best-effort; offline failure still finishes
    ///     the transaction so Apple doesn't re-deliver forever).
    ///   • Transaction finish (required).
    ///   • Entitlement promotion.
    func purchase(_ product: Product) async -> PurchaseOutcome {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                return await handleVerifiedPurchase(verification, expectedProductId: product.id)
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .error(message: "Unknown StoreKit result.")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return .error(message: error.localizedDescription)
        }
    }

    /// Restore purchases — runs `AppStore.sync()` and then scans
    /// `Transaction.currentEntitlements` to re-apply any active entitlements.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    EntitlementStore.shared.apply(
                        productId: transaction.productID,
                        expiresAt: transaction.expirationDate
                    )
                }
            }
            AppLogger.ui.notice("Restore completed")
        } catch {
            lastErrorMessage = error.localizedDescription
            AppLogger.ui.error("Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Transaction updates

    /// Start the long-lived `Transaction.updates` listener. This picks up
    /// renewals, revocations, and family-sharing membership changes that
    /// arrive outside of an explicit purchase.
    private func startTransactionListener() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                _ = await self.handleVerifiedPurchase(update, expectedProductId: nil)
            }
        }
    }

    // MARK: - Internals

    /// Process a verified-or-unverified `Transaction` (from either a direct
    /// purchase or the `.updates` stream). Applies it to the entitlement
    /// store, mirrors to the backend, and finishes the transaction.
    private func handleVerifiedPurchase(
        _ verification: VerificationResult<Transaction>,
        expectedProductId: String?
    ) async -> PurchaseOutcome {
        switch verification {
        case .unverified(_, let error):
            AppLogger.ui.error("StoreKit unverified transaction: \(error.localizedDescription)")
            return .verificationFailed

        case .verified(let transaction):
            // Defence: if caller expected a specific product and StoreKit
            // returned a different one (shouldn't happen), bail rather
            // than grant the wrong entitlement.
            if let expected = expectedProductId, transaction.productID != expected {
                AppLogger.ui.error(
                    "StoreKit product mismatch: expected \(expected), got \(transaction.productID)"
                )
                await transaction.finish()
                return .error(message: "Product ID mismatch.")
            }

            // Local apply FIRST so the UI updates even if the server leg
            // fails (offline purchase scenario).
            EntitlementStore.shared.apply(
                productId: transaction.productID,
                expiresAt: transaction.expirationDate
            )

            // Best-effort server mirror. On failure we log but still
            // finish the transaction — Apple would otherwise re-deliver
            // it forever. The next app boot will reconcile via
            // `EntitlementStore.refresh()`.
            if let api = apiClient {
                do {
                    _ = try await api.verifySubscription(
                        APISubscriptionVerifyPayload(
                            signedTransactionPayload: transaction.jsonRepresentation.base64EncodedString(),
                            signedRenewalInfoPayload: nil
                        )
                    )
                } catch {
                    AppLogger.ui.error("Backend verify failed: \(error.localizedDescription)")
                }
            }

            await transaction.finish()
            return .success(
                productId: transaction.productID,
                expiresAt: transaction.expirationDate
            )
        }
    }
}

// MARK: - Product display helpers

extension Product {
    /// Seven-day-free-trial intro offer, if the product has one configured.
    /// The paywall renders this as "7-day free trial" next to the price.
    var freeTrialOffer: Product.SubscriptionOffer? {
        guard let offer = subscription?.introductoryOffer else { return nil }
        if offer.paymentMode == .freeTrial { return offer }
        return nil
    }

    /// Rendered as "$4.99 / month" — locale-aware via `displayPrice` + the
    /// product's own `subscriptionPeriod`.
    var periodDisplayPrice: String {
        guard let sub = subscription else { return displayPrice }
        let periodText: String = {
            let unitCount = sub.subscriptionPeriod.value
            let unit: String = {
                switch sub.subscriptionPeriod.unit {
                case .day:   return unitCount == 1 ? "day"   : "days"
                case .week:  return unitCount == 1 ? "week"  : "weeks"
                case .month: return unitCount == 1 ? "month" : "months"
                case .year:  return unitCount == 1 ? "year"  : "years"
                @unknown default: return ""
                }
            }()
            return unitCount == 1 ? unit : "\(unitCount) \(unit)"
        }()
        return "\(displayPrice) / \(periodText)"
    }

    /// "7-day free trial" style label. Only defined when an intro offer
    /// with `.freeTrial` payment mode is present.
    var freeTrialLabel: String? {
        guard let offer = freeTrialOffer else { return nil }
        let count = offer.period.value
        let unit: String = {
            switch offer.period.unit {
            case .day:   return count == 1 ? "day"   : "days"
            case .week:  return count == 1 ? "week"  : "weeks"
            case .month: return count == 1 ? "month" : "months"
            case .year:  return count == 1 ? "year"  : "years"
            @unknown default: return ""
            }
        }()
        return "\(count)-\(unit) free trial"
    }
}
