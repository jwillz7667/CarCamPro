import SwiftUI

/// Shared chrome for every onboarding screen.
///
/// Matches the system-grouped feel of iOS's own Setup assistants:
/// `systemGroupedBackground`, large title at the top, content, and a
/// bottom-anchored primary button. A step counter ("Step 2 of 4") sits in
/// the top trailing corner where the user expects a close button in setup
/// flows — intentionally subtle so it doesn't pull focus from the content.
struct OnboardingFrame<Content: View, Footer: View>: View {
    let step: Int
    let total: Int
    let content: () -> Content
    let footer: () -> Footer

    init(
        step: Int,
        total: Int = 4,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.step = step
        self.total = total
        self.content = content
        self.footer = footer
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: CCTheme.Space.xl) {
                        content()
                    }
                    .padding(.horizontal, CCTheme.Space.xl)
                    .padding(.top, CCTheme.Space.xl + 44)
                    .padding(.bottom, CCTheme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: CCTheme.Space.sm) {
                    footer()
                }
                .padding(.horizontal, CCTheme.Space.xl)
                .padding(.bottom, CCTheme.Space.xl)
                .background(Color(.systemGroupedBackground))
            }

            progressHeader
        }
    }

    private var progressHeader: some View {
        HStack {
            Text("Setup")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(step) of \(total)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, CCTheme.Space.xl)
        .padding(.top, CCTheme.Space.md)
    }
}

/// Primary filled button — the canonical "next" action for onboarding.
struct OnboardingPrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(CCTheme.accent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: CCTheme.radiusButton))
        .sensoryFeedback(.selection, trigger: title)
    }
}

/// Secondary ("skip", "configure individually") button.
struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(CCTheme.accent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: CCTheme.radiusButton))
    }
}

/// Section header used inside onboarding scroll content.
struct OnboardingTitle: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CCTheme.Space.sm) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(CCTheme.accent)
            }
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
