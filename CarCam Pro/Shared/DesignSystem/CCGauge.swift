import SwiftUI

/// Circular gauge — arc track + tick ladder + centered readout.
/// Draws a 270° sweep starting at 135° (classic bottom-facing speedometer).
struct CCGauge: View {
    var value: Double
    var maxValue: Double = 100
    var size: CGFloat = 180
    var label: String?
    var unit: String?
    var sublabel: String?
    var color: Color = CCTheme.amber
    var startAngle: Double = 135
    var sweep: Double = 270

    private let tickCount: Int = 41

    private var progress: Double {
        min(max(value / maxValue, 0), 1)
    }

    var body: some View {
        let radius = size / 2 - 8
        let center = CGPoint(x: size / 2, y: size / 2)

        ZStack {
            Canvas { ctx, _ in
                // base track
                let trackPath = arcPath(from: startAngle,
                                        to: startAngle + sweep,
                                        center: center, radius: radius)
                ctx.stroke(trackPath, with: .color(CCTheme.rule), lineWidth: 1)

                // filled arc
                let fillPath = arcPath(from: startAngle,
                                       to: startAngle + sweep * progress,
                                       center: center, radius: radius)
                ctx.stroke(fillPath, with: .color(color), lineWidth: 2)

                // ticks
                for i in 0..<tickCount {
                    let t = Double(i) / Double(tickCount - 1)
                    let angle = startAngle + sweep * t
                    let isMajor = i % 5 == 0
                    let inner = radius - (isMajor ? 10 : 5)
                    let p1 = polar(angle: angle, radius: radius, center: center)
                    let p2 = polar(angle: angle, radius: inner, center: center)
                    let filled = t <= progress
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    ctx.stroke(
                        path,
                        with: .color(filled ? color : CCTheme.ink4),
                        lineWidth: isMajor ? 1.5 : 1
                    )
                }
            }

            VStack(spacing: 2) {
                if let label { CCLabel(label, size: 9) }
                CCNum(
                    value: formattedValue,
                    unit: unit,
                    size: size * 0.28,
                    weight: .ultraLight,
                    color: color
                )
                if let sublabel { CCLabel(sublabel, size: 9, color: CCTheme.ink4) }
            }
        }
        .frame(width: size, height: size)
    }

    private var formattedValue: String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func polar(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let rad = (angle - 90) * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(rad)),
            y: center.y + radius * CGFloat(sin(rad))
        )
    }

    private func arcPath(from startDeg: Double, to endDeg: Double, center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let start = polar(angle: startDeg, radius: radius, center: center)
        path.move(to: start)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDeg - 90),
            endAngle: .degrees(endDeg - 90),
            clockwise: false
        )
        return path
    }
}
