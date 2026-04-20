import SwiftUI

/// Diagonal-stripe placeholder used wherever a live feed would go in a mockup.
/// Collapses to a thin stamp label when rendered at small sizes.
struct CCFeedPlaceholder<Content: View>: View {
    var label: String = "LIVE FEED"
    @ViewBuilder var content: () -> Content

    init(label: String = "LIVE FEED", @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.label = label
        self.content = content
    }

    var body: some View {
        ZStack {
            StripePattern()

            VStack(spacing: 0) {
                CCLabel(label, size: 10, color: CCTheme.ink3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
            }

            content()
        }
        .clipped()
    }
}

/// 135° repeating stripes, drawn procedurally so it scales with the container.
private struct StripePattern: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(CCTheme.panel))

            let spacing: CGFloat = 15
            let diag = size.width + size.height
            var x: CGFloat = -size.height
            while x < diag {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.stroke(p, with: .color(CCTheme.panelHi), lineWidth: 1)
                x += spacing
            }
        }
    }
}
