import SwiftUI

/// Shared chrome for every onboarding screen — version tag, step counter,
/// and bottom progress bar. Matches the `OnboardFrame` primitive in the mockup.
struct OnboardingFrame<Content: View>: View {
    let step: Int
    let total: Int
    let content: () -> Content

    init(step: Int, total: Int = 4, @ViewBuilder content: @escaping () -> Content) {
        self.step = step
        self.total = total
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            CCTheme.void.ignoresSafeArea()

            content()

            HStack {
                CCLabel("CARCAM / v4.2", size: 9)
                Spacer()
                HStack(spacing: 4) {
                    CCLabel(String(format: "%02d", step), size: 9, color: CCTheme.amber)
                    CCLabel("/ \(String(format: "%02d", total))", size: 9, color: CCTheme.ink4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 54)

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<total, id: \.self) { i in
                        Rectangle()
                            .fill(i < step ? CCTheme.amber : CCTheme.rule)
                            .frame(height: 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 54)
            }
        }
    }
}

/// Primary/secondary button used across onboarding. Mono letter-spaced glyph.
struct OnboardingButton: View {
    let title: String
    var primary: Bool = false
    var trailingIcon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title.uppercased())
                    .font(CCFont.mono(12, weight: .medium))
                    .kerning(2.4)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 13, weight: .regular))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(primary ? CCTheme.void : CCTheme.ink)
            .background(primary ? CCTheme.amber : Color.clear)
            .overlay(
                Rectangle().stroke(primary ? Color.clear : CCTheme.ruleHi, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: primary)
    }
}
