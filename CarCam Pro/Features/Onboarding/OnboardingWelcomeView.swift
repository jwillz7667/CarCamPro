import SwiftUI

/// Step 1 — welcome / brand. Aperture mark + editorial headline + spec grid.
struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingFrame(step: 1) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                ApertureMark(size: 96)
                    .padding(.bottom, 48)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Your phone.\nYour witness.")
                        .font(CCFont.display(44, weight: .light))
                        .kerning(-1.3)
                        .foregroundStyle(CCTheme.ink)
                        .lineSpacing(-4)

                    Text("A continuously recording dash cam. Loop captures, automatic incident locking, GPS telemetry — all on-device.")
                        .font(CCFont.sans(15))
                        .foregroundStyle(CCTheme.ink2)
                        .lineSpacing(4)
                        .frame(maxWidth: 320, alignment: .leading)
                }
                .padding(.bottom, 48)

                SpecGrid()
                    .padding(.bottom, 40)

                Spacer()

                OnboardingButton(title: "Begin setup", primary: true, trailingIcon: "arrow.right") {
                    onContinue()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 110)
            .padding(.bottom, 90)
        }
    }
}

private struct SpecGrid: View {
    private let cells: [(String, String)] = [
        ("1440p", "Capture"),
        ("60fps", "Framerate"),
        ("H.265", "Codec"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                VStack(alignment: .leading, spacing: 4) {
                    Text(cell.0)
                        .font(CCFont.mono(18, weight: .regular))
                        .foregroundStyle(CCTheme.ink)
                    CCLabel(cell.1, size: 9, color: CCTheme.ink4)
                }
                .padding(.vertical, 16)
                .padding(.leading, idx == 0 ? 0 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if idx > 0 {
                        Rectangle().fill(CCTheme.rule).frame(width: 1)
                    }
                }
            }
        }
        .overlay(Rectangle().stroke(CCTheme.rule, lineWidth: 1).frame(maxHeight: .infinity, alignment: .top), alignment: .top)
        .overlay(alignment: .top) { Rectangle().fill(CCTheme.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(CCTheme.rule).frame(height: 1) }
    }
}
