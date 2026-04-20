import SwiftUI

/// The five top-level tabs of the application shell.
enum CCTab: String, CaseIterable, Identifiable {
    case home, live, map, trips, settings
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

/// Bottom tab bar with an amber top-border underline on the active tab.
/// Hit area is the full height of each cell; text is mono/tracked.
struct CCTabBar: View {
    @Binding var active: CCTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CCTheme.rule)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(CCTab.allCases) { tab in
                    Button {
                        active = tab
                    } label: {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(active == tab ? CCTheme.amber : .clear)
                                .frame(height: 1)
                            CCLabel(
                                tab.title,
                                size: 9,
                                color: active == tab ? CCTheme.amber : CCTheme.ink4
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
            .background(CCTheme.bg)
        }
    }
}
