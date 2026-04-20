import SwiftUI

/// Root view of the onboarding flow. Owns the shared `OnboardingState` and
/// animates between steps. The parent shell swaps to `MainTabView` once the
/// state reports completion.
struct OnboardingFlowView: View {
    @State private var state = OnboardingState()
    let onCompleted: () -> Void

    var body: some View {
        ZStack {
            CCTheme.void.ignoresSafeArea()

            switch state.step {
            case .welcome:
                OnboardingWelcomeView { state.advance() }
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
