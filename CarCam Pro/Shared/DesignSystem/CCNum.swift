import SwiftUI

/// Monospaced numeric readout with an optional unit label.
/// Mirrors the `CCNum` primitive from the design system: large tabular digit
/// with a small uppercase unit sitting on the baseline.
struct CCNum: View {
    let value: String
    var unit: String?
    var size: CGFloat = 48
    var weight: Font.Weight = .light
    var color: Color = CCTheme.ink
    var unitColor: Color = CCTheme.ink3

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(CCFont.mono(size, weight: weight))
                .monospacedDigit()
                .kerning(-size * 0.02)
                .foregroundStyle(color)

            if let unit, !unit.isEmpty {
                Text(unit.uppercased())
                    .font(CCFont.mono(max(10, size * 0.22), weight: .medium))
                    .kerning(max(10, size * 0.22) * 0.16)
                    .foregroundStyle(unitColor)
            }
        }
    }
}
