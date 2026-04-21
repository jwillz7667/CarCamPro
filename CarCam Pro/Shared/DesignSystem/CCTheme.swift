import SwiftUI

/// Design tokens — the palette is iOS-native system colors wherever possible,
/// with CarCam's amber as the only branded accent. Every UI surface should
/// prefer `Color.*` system semantics over these tokens so the app feels
/// native on every iOS version.
enum CCTheme {
    // MARK: Branded accent
    /// Primary brand accent (amber). Pairs with `.tint(CCTheme.accent)` at the
    /// app root so every native control (Picker, Toggle, NavigationLink
    /// chevron) picks it up automatically.
    static let accent          = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)

    // MARK: Signal colors (iOS dark variants — match system feel)
    static let amber           = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    static let cyan            = Color(red: 0x64 / 255, green: 0xD2 / 255, blue: 0xFF / 255)
    static let red             = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
    static let green           = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    static let blue            = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)

    // MARK: Corner radius tokens
    static let radiusPill:   CGFloat = 9999
    static let radiusLarge:  CGFloat = 26      // iOS inset-grouped list cards
    static let radiusCard:   CGFloat = 20
    static let radiusButton: CGFloat = 14
    static let radiusInput:  CGFloat = 12

    // MARK: Spacing tokens
    enum Space {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }
}

/// Typography — SF Pro everywhere. Display is rounded for marketing/hero
/// surfaces (Home title), Text is default for body, Mono reserved for
/// numeric readouts only (timecodes, speed, g-force).
enum CCFont {
    /// Rounded SF Pro — used for dashboard hero text.
    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Monospaced digits — used for live numeric readouts (speed, timecode).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Default SF Pro — body text, titles, captions. Use the standard
    /// dynamic-type text styles (`.title`, `.body`, etc.) directly in views
    /// when possible; this helper is only for non-standard sizes.
    static func system(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
