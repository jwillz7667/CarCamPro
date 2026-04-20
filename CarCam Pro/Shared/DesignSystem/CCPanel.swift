import SwiftUI

/// Translucent HUD panel — dark fill + hairline border. Used for every floating
/// telemetry card in the live/map views (replaces the raw `rgba(...)` + border
/// pattern found throughout the mockups).
struct CCPanel<Content: View>: View {
    var padding: CGFloat = 12
    var borderColor: Color = CCTheme.ruleHi
    var background: Color = Color.black.opacity(0.55)
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = 12,
        borderColor: Color = CCTheme.ruleHi,
        background: Color = Color.black.opacity(0.55),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.borderColor = borderColor
        self.background = background
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(background)
            .overlay(Rectangle().stroke(borderColor, lineWidth: 1))
    }
}

/// Two-tone mono readout: small caps label above a big mono number.
struct CCReadout: View {
    var label: String
    var value: String
    var unit: String?
    var valueSize: CGFloat = 18
    var color: Color = CCTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CCLabel(label, size: 8, color: CCTheme.ink4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(CCFont.mono(valueSize, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(color)
                if let unit, !unit.isEmpty {
                    Text(unit.uppercased())
                        .font(CCFont.mono(9, weight: .medium))
                        .kerning(0.9)
                        .foregroundStyle(CCTheme.ink4)
                }
            }
        }
    }
}
