import SwiftUI

/// Root shell of the application after onboarding. Uses the native iOS 26
/// `TabView` so the tab bar automatically picks up Liquid Glass, the new
/// expanded-pill selection indicator, and dynamic-type scaling for free.
///
/// The LIVE tab intentionally appears in the center slot — that's where the
/// user's thumb naturally lands and where the most important action (hit
/// "record") lives.
struct MainTabView: View {
    @State private var selection: MainTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: MainTab.home) {
                HomeDashboardView()
            }

            Tab("Live", systemImage: "video.circle.fill", value: MainTab.live) {
                LiveCamView()
            }

            Tab("Map", systemImage: "map.fill", value: MainTab.map) {
                MapDashboardView()
            }

            Tab("Trips", systemImage: "list.bullet.rectangle.fill", value: MainTab.trips) {
                TripsListView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: MainTab.settings) {
                SettingsView()
            }
        }
        .tint(CCTheme.accent)
    }
}

enum MainTab: Hashable {
    case home, live, map, trips, settings
}
