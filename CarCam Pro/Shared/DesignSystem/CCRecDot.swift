import SwiftUI

/// Pulsing circular recording indicator. Used in HUDs and list rows.
struct CCRecDot: View {
    var size: CGFloat = 8
    var color: Color = CCTheme.red

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color, radius: size, x: 0, y: 0)
            .opacity(pulsing ? 0.35 : 1.0)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
