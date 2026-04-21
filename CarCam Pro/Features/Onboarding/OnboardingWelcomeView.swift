import SwiftUI

/// Step 1 — welcome / brand.
///
/// Purposefully minimal: a hero SF Symbol, a large rounded headline, one
/// supporting paragraph, and a spec strip. The layout deliberately mirrors
/// Apple's own app-first-launch sheets (e.g. Shortcuts, Journal).
struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingFrame(step: 1, total: 6) {
            heroImage
                .padding(.vertical, CCTheme.Space.md)

            OnboardingTitle(
                eyebrow: nil,
                title: "Your phone.\nYour witness.",
                subtitle: "A continuously recording dash cam. Loop captures, automatic incident locking, GPS telemetry — all on-device."
            )

            SpecGrid()
        } footer: {
            OnboardingPrimaryButton(title: "Continue", systemImage: "arrow.right") {
                onContinue()
            }
        }
    }

    private var heroImage: some View {
        Image(systemName: "camera.aperture")
            .font(.system(size: 96, weight: .ultraLight))
            .foregroundStyle(CCTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

private struct SpecGrid: View {
    private let cells: [(String, String, String)] = [
        ("1440p", "Capture", "video.fill"),
        ("60fps", "Framerate", "speedometer"),
        ("H.265", "Codec", "doc.on.doc.fill"),
    ]

    var body: some View {
        HStack(spacing: CCTheme.Space.md) {
            ForEach(cells, id: \.0) { cell in
                specCell(value: cell.0, label: cell.1, symbol: cell.2)
            }
        }
    }

    private func specCell(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: CCTheme.Space.sm) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(CCTheme.accent)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(CCTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
