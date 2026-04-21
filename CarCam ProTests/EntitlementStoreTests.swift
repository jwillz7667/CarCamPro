import Foundation
import Testing
@testable import CarCam_Pro

/// Unit coverage for the product-ID → tier mapping and the paywall's
/// no-downgrade rule. These decisions gate every paid feature in the app
/// so regressions here are user-visible immediately.
@Suite("EntitlementStore — tier mapping + promotion rules", .serialized)
struct EntitlementStoreTests {

    @Test("productId to tier — premium wins keywords")
    func premiumKeyword() {
        #expect(EntitlementStore.tier(forProductId: "pro.carcam.premium.monthly") == .premium)
        #expect(EntitlementStore.tier(forProductId: "pro.carcam.premium.yearly")  == .premium)
        #expect(EntitlementStore.tier(forProductId: "SOMETHING.Premium.whatever") == .premium)
    }

    @Test("productId to tier — pro keyword")
    func proKeyword() {
        #expect(EntitlementStore.tier(forProductId: "pro.carcam.pro.monthly") == .pro)
        #expect(EntitlementStore.tier(forProductId: "pro.carcam.pro.yearly")  == .pro)
    }

    @Test("productId to tier — unknown falls back to free")
    func unknownFallsBackToFree() {
        #expect(EntitlementStore.tier(forProductId: "") == .free)
        #expect(EntitlementStore.tier(forProductId: "com.example.unrelated") == .free)
    }

    @Test("apply(productId:) promotes but never demotes")
    @MainActor
    func applyPromotesOnly() {
        let store = EntitlementStore.shared
        store.markSignedOut() // reset to .free
        #expect(store.tier == .free)

        // Free → Pro is a promotion.
        store.apply(productId: "pro.carcam.pro.monthly", expiresAt: nil)
        #expect(store.tier == .pro)

        // Pro → Premium is a promotion.
        store.apply(productId: "pro.carcam.premium.monthly", expiresAt: nil)
        #expect(store.tier == .premium)

        // Premium → Pro via a stale StoreKit transaction must NOT demote.
        store.apply(productId: "pro.carcam.pro.yearly", expiresAt: nil)
        #expect(store.tier == .premium)

        store.markSignedOut()
    }

    @Test("feature gates derive correctly from tier")
    @MainActor
    func featureGates() {
        let store = EntitlementStore.shared
        store.markSignedOut()
        #expect(store.maxResolution == .hd720)
        #expect(store.canRecordInBackground == false)
        #expect(store.incidentBufferSeconds == 30)

        store.apply(productId: "pro.carcam.pro.monthly", expiresAt: nil)
        #expect(store.maxResolution == .hd1080)
        #expect(store.canRecordInBackground == true)
        #expect(store.incidentBufferSeconds == 30)

        store.apply(productId: "pro.carcam.premium.monthly", expiresAt: nil)
        #expect(store.maxResolution == .uhd4k)
        #expect(store.canRecordInBackground == true)
        #expect(store.incidentBufferSeconds == 60)

        store.markSignedOut()
    }
}

/// Coverage for the updated 6-step onboarding state machine (welcome →
/// signIn → permissions → calibration → paywall → ready).
@Suite("OnboardingState — step progression", .serialized)
struct OnboardingStateTests {

    @Test("Six-step ordering + total")
    @MainActor
    func sixStepOrder() {
        let steps = OnboardingState.Step.allCases.map(\.rawValue).sorted()
        #expect(steps == [1, 2, 3, 4, 5, 6])
        #expect(OnboardingState.Step.welcome.total == 6)
    }

    @Test("advance walks the flow end-to-end and marks complete at tail")
    @MainActor
    func advanceCompletes() {
        let s = OnboardingState()
        s.reset()
        #expect(s.step == .welcome)
        s.advance(); #expect(s.step == .signIn)
        s.advance(); #expect(s.step == .permissions)
        s.advance(); #expect(s.step == .calibration)
        s.advance(); #expect(s.step == .paywall)
        s.advance(); #expect(s.step == .ready)
        // Advancing past .ready flips isCompleted.
        s.advance()
        #expect(s.isCompleted == true)
        s.reset()
    }

    @Test("goBack moves one step; no underflow below .welcome")
    @MainActor
    func goBackClamps() {
        let s = OnboardingState()
        s.reset()
        s.advance() // → signIn
        s.goBack()
        #expect(s.step == .welcome)
        s.goBack()
        #expect(s.step == .welcome) // clamp, no crash
    }
}
