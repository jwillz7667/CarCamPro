import SwiftUI
import StoreKit
import OSLog

/// Subscription paywall — the money screen.
///
/// Two presentation contexts:
///   1. **Inside onboarding** — stepCount = 5 of 6; "Not now" keeps the
///      user on FREE and advances the flow. Purchase / restore also
///      advance.
///   2. **Ad hoc from Settings** — presented as a sheet with a close
///      button; same purchase mechanics.
///
/// Shows up to four products in two rows:
///   • Pro monthly · Pro yearly
///   • Premium monthly · Premium yearly  ← highlighted as recommended
///
/// The 7-day free trial is surfaced per-product via
/// `Product.freeTrialLabel`; StoreKit automatically applies the intro
/// offer on first purchase for eligible users. Trial-eligibility is
/// checked via `Product.subscription.isEligibleForIntroOffer`.
struct PaywallView: View {
    enum Context {
        case onboarding
        case settings
    }

    let context: Context
    let onCompleted: () -> Void
    let onSkipped: () -> Void

    @State private var store = StoreKitManager.shared
    @State private var entitlements = EntitlementStore.shared
    @State private var selectedProductId: String = "pro.carcam.premium.monthly"
    @State private var errorMessage: String?
    @State private var trialEligibility: [String: Bool] = [:]

    var body: some View {
        switch context {
        case .onboarding:
            OnboardingFrame(step: 5, total: 6) {
                content
            } footer: {
                footer
            }
            .task { await load() }
        case .settings:
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: CCTheme.Space.xl) {
                        content
                    }
                    .padding(CCTheme.Space.xl)
                }
                .safeAreaInset(edge: .bottom) {
                    footer
                        .padding(CCTheme.Space.lg)
                        .background(Color(.systemGroupedBackground))
                }
                .navigationTitle("Upgrade")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { onSkipped() }
                    }
                }
                .task { await load() }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        heroHeader
        benefitsMatrix
        productGrid
        legalFooter
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: CCTheme.Space.sm) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(CCTheme.accent)
                .accessibilityHidden(true)
                .padding(.bottom, CCTheme.Space.sm)

            Text("Unlock the full dashcam.")
                .font(.largeTitle.weight(.bold))

            Text("Start free for 7 days. Cancel anytime.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var benefitsMatrix: some View {
        VStack(spacing: 0) {
            benefitRow(title: "Capture resolution",
                       free: "720p", pro: "1080p", premium: "4K")
            Divider().opacity(0.3)
            benefitRow(title: "Storage",
                       free: "2 GB", pro: "10 GB", premium: "Unlimited")
            Divider().opacity(0.3)
            benefitRow(title: "Background recording",
                       free: "—", pro: "✓", premium: "✓")
            Divider().opacity(0.3)
            benefitRow(title: "Incident reports",
                       free: "—", pro: "✓", premium: "✓ · 60s buffer")
            Divider().opacity(0.3)
            benefitRow(title: "Cloud backup",
                       free: "—", pro: "✓", premium: "✓")
        }
        .padding(.vertical, CCTheme.Space.sm)
        .padding(.horizontal, CCTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func benefitRow(title: String, free: String, pro: String, premium: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .frame(width: 60).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            Text(pro)
                .frame(width: 60).font(.footnote.weight(.medium)).monospacedDigit()
            Text(premium)
                .frame(width: 120, alignment: .trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CCTheme.accent)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Product grid

    private var productGrid: some View {
        VStack(spacing: CCTheme.Space.md) {
            let orderedProducts = StoreKitManager.displayOrder.compactMap { store.products[$0] }
            if orderedProducts.isEmpty {
                productLoadingState
            } else {
                ForEach(orderedProducts, id: \.id) { product in
                    productCard(product: product)
                }
            }
        }
    }

    private var productLoadingState: some View {
        HStack(spacing: CCTheme.Space.md) {
            ProgressView()
            Text(store.isWorking ? "Loading plans…" : "Plans unavailable — check your connection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(CCTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func productCard(product: Product) -> some View {
        let isSelected = selectedProductId == product.id
        let isRecommended = product.id == "pro.carcam.premium.monthly"
        let isTrialEligible = trialEligibility[product.id] ?? false

        return Button {
            selectedProductId = product.id
        } label: {
            HStack(spacing: CCTheme.Space.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? CCTheme.accent : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(productDisplayName(product.id))
                            .font(.headline)
                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(CCTheme.accent.opacity(0.18))
                                )
                                .foregroundStyle(CCTheme.accent)
                        }
                    }
                    Text(product.periodDisplayPrice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isTrialEligible, let trial = product.freeTrialLabel {
                        Text("Start with a \(trial). Cancel anytime.")
                            .font(.caption)
                            .foregroundStyle(CCTheme.green)
                    }
                }
                Spacer()
            }
            .padding(CCTheme.Space.md)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .strokeBorder(isSelected ? CCTheme.accent : Color.clear, lineWidth: 2)
        )
    }

    private func productDisplayName(_ id: String) -> String {
        let tier: String = id.contains("premium") ? "Premium" : "Pro"
        let cadence: String = id.contains("yearly") ? "Yearly" : "Monthly"
        return "CarCam \(tier) · \(cadence)"
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: CCTheme.Space.sm) {
            Text("Payment is charged to your Apple ID on confirmation. Free trials convert to paid subscriptions unless cancelled at least 24 hours before the trial ends. Manage in Settings → Apple ID → Subscriptions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: CCTheme.Space.md) {
                Link("Terms of Service", destination: URL(string: "https://carcam.pro/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://carcam.pro/privacy")!)
            }
            .font(.caption)
        }
    }

    // MARK: - Footer (buttons)

    private var footer: some View {
        VStack(spacing: CCTheme.Space.sm) {
            OnboardingPrimaryButton(
                title: primaryButtonTitle,
                systemImage: store.isWorking ? nil : "sparkles"
            ) {
                Task { await purchaseSelected() }
            }
            .disabled(store.isWorking || store.products[selectedProductId] == nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(CCTheme.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: CCTheme.Space.md) {
                Button("Restore Purchases") {
                    Task { await restore() }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(CCTheme.accent)
                .disabled(store.isWorking)

                Spacer()

                if case .onboarding = context {
                    Button("Not now") { onSkipped() }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        guard let product = store.products[selectedProductId] else { return "Continue" }
        if trialEligibility[product.id] ?? false, let trial = product.freeTrialLabel {
            return "Start \(trial)"
        }
        return "Subscribe — \(product.displayPrice)"
    }

    // MARK: - Actions

    private func load() async {
        await store.load()
        await refreshTrialEligibility()
        // If the user is already subscribed, don't make them purchase again —
        // auto-advance the onboarding flow.
        if entitlements.tier.meets(.pro) {
            onCompleted()
        }
    }

    private func refreshTrialEligibility() async {
        var map: [String: Bool] = [:]
        for product in store.products.values {
            guard let sub = product.subscription else { continue }
            map[product.id] = await sub.isEligibleForIntroOffer
        }
        trialEligibility = map
    }

    private func purchaseSelected() async {
        errorMessage = nil
        guard let product = store.products[selectedProductId] else { return }
        let result = await store.purchase(product)
        switch result {
        case .success:
            entitlements.hasSeenPaywall = true
            onCompleted()
        case .pending:
            errorMessage = "Purchase pending approval. We'll unlock your features automatically once it clears."
        case .userCancelled, .verificationFailed:
            // Silent on cancel; log-only for verification failure.
            if case .verificationFailed = result {
                errorMessage = "Apple couldn't verify the purchase. Try again or contact support."
            }
        case .error(let message):
            errorMessage = message
        }
    }

    private func restore() async {
        errorMessage = nil
        await store.restore()
        if entitlements.tier.meets(.pro) {
            entitlements.hasSeenPaywall = true
            onCompleted()
        } else {
            errorMessage = "No active subscription found on this Apple ID."
        }
    }
}
