import SwiftUI

/// Corner crosshair overlay — four L-shaped brackets pinned to the corners
/// of the containing rect. Adds a "technical framing" feel around placeholders.
struct CCCrosshair: View {
    var color: Color = CCTheme.ink4
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            corner(top: true, leading: true)
            corner(top: true, leading: false)
            corner(top: false, leading: true)
            corner(top: false, leading: false)
        }
        .allowsHitTesting(false)
    }

    private func corner(top: Bool, leading: Bool) -> some View {
        Path { path in
            let h = size
            let v = size
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: h, y: 0))
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: v))
        }
        .stroke(color, lineWidth: 1)
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotationFor(top: top, leading: leading)))
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: alignment(top: top, leading: leading))
    }

    private func rotationFor(top: Bool, leading: Bool) -> Double {
        switch (top, leading) {
        case (true, true):   return 0
        case (true, false):  return 90
        case (false, false): return 180
        case (false, true):  return 270
        }
    }

    private func alignment(top: Bool, leading: Bool) -> Alignment {
        switch (top, leading) {
        case (true, true):   return .topLeading
        case (true, false):  return .topTrailing
        case (false, true):  return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }
}
