import SwiftUI

/// Overlay drawn on top of the live camera preview: colored threat boxes +
/// a top-of-screen alert banner for the most severe active threat.
///
/// Uses iOS 26 Liquid Glass for the banner so it floats naturally over the
/// preview; threat boxes are rounded rectangles sized to the Vision-space
/// bounding boxes from the detector.
struct DetectionOverlayView: View {
    @State private var manager = AlertManager.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(manager.activeThreats) { threat in
                    ThreatBox(threat: threat, viewSize: proxy.size)
                }
                if let worst = manager.activeThreats.max(by: { $0.fusedScore < $1.fusedScore }),
                   worst.threatLevel >= .likely {
                    AlertBanner(threat: worst)
                        .padding(.horizontal, CCTheme.Space.lg)
                        .padding(.top, CCTheme.Space.sm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.snappy, value: manager.activeThreats.map(\.id))
    }
}

// MARK: - Threat box

private struct ThreatBox: View {
    let threat: VehicleThreatAssessment
    let viewSize: CGSize

    var body: some View {
        let bbox = threat.detection.boundingBox
        let rect = CGRect(
            x: bbox.origin.x * viewSize.width,
            y: (1 - bbox.origin.y - bbox.size.height) * viewSize.height,
            width: bbox.size.width * viewSize.width,
            height: bbox.size.height * viewSize.height
        )

        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(color, lineWidth: threat.threatLevel >= .likely ? 3 : 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .overlay(
                // Confidence pill in the top-left corner of the box.
                Text("\(Int(threat.fusedScore * 100))%")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(color))
                    .position(x: rect.minX + 24, y: rect.minY + 12)
            )
    }

    private var color: Color {
        switch threat.threatLevel {
        case .confirmed: return CCTheme.red
        case .likely:    return CCTheme.amber
        case .possible:  return CCTheme.cyan
        case .low, .none: return .gray
        }
    }
}

// MARK: - Banner

private struct AlertBanner: View {
    let threat: VehicleThreatAssessment

    var body: some View {
        HStack(spacing: CCTheme.Space.md) {
            Image(systemName: iconName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if !threat.reasoning.isEmpty {
                    Text(threat.reasoning.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, CCTheme.Space.lg)
        .padding(.vertical, CCTheme.Space.md)
        .glassEffect(.regular.tint(tint.opacity(0.35)), in: .rect(cornerRadius: CCTheme.radiusLarge))
    }

    private var title: String {
        switch threat.threatLevel {
        case .confirmed: return "Emergency vehicle ahead"
        case .likely:    return "Possible law enforcement vehicle"
        case .possible:  return "Suspicious vehicle detected"
        default:         return ""
        }
    }

    private var iconName: String {
        switch threat.threatLevel {
        case .confirmed: return "exclamationmark.triangle.fill"
        case .likely:    return "exclamationmark.shield.fill"
        default:         return "eye.fill"
        }
    }

    private var tint: Color {
        threat.threatLevel == .confirmed ? CCTheme.red : CCTheme.amber
    }
}
