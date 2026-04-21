import SwiftUI

/// Shared style enum for every glass control. Extracted from the generic
/// `GlassPillButton` so it can be used as a standalone parameter type on
/// non-generic controls (`GlassIconButton`, `GlassBackground`).
enum GlassStyle {
    case regular
    case tinted(Color)
    case prominent   // filled accent
    case destructive // filled red
}

/// A capsule-shaped glass button — the standard Liquid Glass control used
/// everywhere a button needs to float over a live camera preview, a map, or
/// a photo. Uses the iOS 26 `.glassEffect(.regular.interactive(), in: …)`
/// modifier so the button responds to press with the system's shimmer.
struct GlassPillButton<Label: View>: View {
    let style: GlassStyle
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    init(
        style: GlassStyle = .regular,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.style = style
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, CCTheme.Space.lg)
                .padding(.vertical, CCTheme.Space.md)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .modifier(GlassBackground(style: style))
        .contentShape(.capsule)
    }

    private var foreground: Color {
        switch style {
        case .regular, .tinted:         return .white
        case .prominent, .destructive:  return .white
        }
    }
}

/// Glass circle button — for single-glyph controls like flip-camera, share,
/// or the LOCK button in the live HUD.
struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 52
    var style: GlassStyle = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .modifier(GlassBackground(style: style, shape: AnyShape(Circle())))
    }

    private var foreground: Color {
        switch style {
        case .regular, .tinted, .prominent, .destructive: return .white
        }
    }
}

/// Rounded-rect glass card — for inline HUDs (timecode pill, speed readout).
struct GlassStatusPill<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, CCTheme.Space.md)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Background modifier — picks the right glass variant based on the button
/// style and paints the tint underneath. Unified here so every glass control
/// in the app has identical chrome.
private struct GlassBackground: ViewModifier {
    let style: GlassStyle
    var shape: AnyShape = AnyShape(Capsule())

    func body(content: Content) -> some View {
        switch style {
        case .regular:
            content
                .glassEffect(.regular.interactive(), in: shape)

        case .tinted(let color):
            content
                .glassEffect(.regular.tint(color.opacity(0.35)).interactive(), in: shape)

        case .prominent:
            content
                .background(CCTheme.accent, in: shape)
                .glassEffect(.regular.tint(CCTheme.accent.opacity(0.6)).interactive(), in: shape)

        case .destructive:
            content
                .background(CCTheme.red, in: shape)
                .glassEffect(.regular.tint(CCTheme.red.opacity(0.6)).interactive(), in: shape)
        }
    }
}

/// Rounded rect surface — replaces our old square "CCPanel" / "SettingsSection"
/// chrome. Pairs with `.glassEffect()` when floated over live content;
/// falls back to `.regularMaterial` inside list bodies.
struct RoundedCard<Content: View>: View {
    var cornerRadius: CGFloat = CCTheme.radiusCard
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
