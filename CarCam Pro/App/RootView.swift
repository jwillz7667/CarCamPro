import SwiftUI

/// Top-level router — shows onboarding on first launch, then the main tab shell.
/// `@AppStorage` persists the completion flag across launches.
struct RootView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        Group {
            if onboardingCompleted {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlowView {
                    onboardingCompleted = true
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingCompleted)
    }
}
