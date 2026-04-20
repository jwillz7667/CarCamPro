import SwiftUI

/// Dashboard top bar — aperture mark on the left, arbitrary trailing content.
struct CCTopBar<Trailing: View>: View {
    var trailing: () -> Trailing

    init(@ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                ApertureMark()
                CCLabel("CARCAM", size: 10, color: CCTheme.ink)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
    }
}

/// Stylized aperture logo — concentric circle + solid center.
struct ApertureMark: View {
    var size: CGFloat = 18
    var color: Color = CCTheme.amber

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1)
                .frame(width: size, height: size)
            Circle()
                .fill(color)
                .frame(width: size / 4, height: size / 4)
        }
    }
}

/// "ARMED" + storage readout — the canonical right-hand side of dashboards.
struct CCArmedIndicator: View {
    var armed: Bool
    var storageFree: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(armed ? CCTheme.green : CCTheme.ink4)
                    .frame(width: 6, height: 6)
                CCLabel(armed ? "ARMED" : "IDLE",
                        size: 9,
                        color: armed ? CCTheme.green : CCTheme.ink4)
            }
            Rectangle()
                .fill(CCTheme.ruleHi)
                .frame(width: 1, height: 12)
            CCLabel(storageFree, size: 9, color: CCTheme.ink3)
        }
    }
}
