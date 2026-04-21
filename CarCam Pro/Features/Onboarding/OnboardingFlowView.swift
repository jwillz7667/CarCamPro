import SwiftUI

/// Root view of the onboarding flow. Owns the shared `OnboardingState` and
/// animates between steps. The parent shell swaps to `MainTabView` once the
/// state reports completion.
///
/// Step order — welcome → signIn → permissions → calibration → paywall →
/// ready. Sign-in + paywall advance whether the user completes or skips
/// them; EntitlementStore captures the outcome so gating across the app
/// respects it.
struct OnboardingFlowView: View {
    @State private var state = OnboardingState()
    let onCompleted: () -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            switch state.step {
            case .welcome:
                OnboardingWelcomeView { state.advance() }
                    .transition(.opacity)
            case .signIn:
                SignInView(
                    onSignedIn: { state.advance() },
                    onSkipped: { state.advance() }
                )
                .transition(.opacity)
            case .permissions:
                OnboardingPermissionsView { state.advance() }
                    .transition(.opacity)
            case .calibration:
                OnboardingCalibrationView(
                    onContinue: { state.advance() },
                    onSkip: { state.advance() }
                )
                .transition(.opacity)
            case .paywall:
                PaywallView(
                    context: .onboarding,
                    onCompleted: {
                        EntitlementStore.shared.hasSeenPaywall = true
                        state.advance()
                    },
                    onSkipped: {
                        EntitlementStore.shared.hasSeenPaywall = true
                        state.advance()
                    }
                )
                .transition(.opacity)
            case .ready:
                OnboardingReadyView {
                    state.complete()
                    onCompleted()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state.step)
    }
}
