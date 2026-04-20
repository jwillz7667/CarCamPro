import SwiftUI

/// Small-caps "technical" label — mono, tracked, uppercase.
/// Used for all section headers, readout captions, and stamp text.
struct CCLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = CCTheme.ink3

    init(_ text: String, size: CGFloat = 10, color: Color = CCTheme.ink3) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(CCFont.mono(size, weight: .medium))
            .kerning(size * 0.18)
            .foregroundStyle(color)
    }
}
