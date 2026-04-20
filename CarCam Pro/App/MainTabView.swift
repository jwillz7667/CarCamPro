import SwiftUI

/// Root shell of the application after onboarding. Renders the active tab's
/// root view atop the custom bottom `CCTabBar`. The landscape LIVE tab hides
/// the tab bar so the HUD gets full bleed.
struct MainTabView: View {
    @State private var active: CCTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            CCTheme.void.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.keyboard)

            if active != .live {
                CCTabBar(active: $active)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(active == .live)
        .animation(.easeInOut(duration: 0.2), value: active)
    }

    @ViewBuilder
    private var content: some View {
        switch active {
        case .home:     HomeDashboardView(activeTab: $active)
        case .live:     LiveCamView(activeTab: $active)
        case .map:      MapDashboardView(activeTab: $active)
        case .trips:    TripsListView(activeTab: $active)
        case .settings: SettingsView()
        }
    }
}
