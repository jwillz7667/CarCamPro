import SwiftUI

/// Design tokens for the CarCam "technical instrument-cluster" aesthetic.
/// All colors mirror the iOS 26 dark system palette, with a small set of
/// branded signal colors (amber = primary accent, cyan = telemetry, etc.).
enum CCTheme {
    // MARK: Surfaces
    static let void            = rgb(0x00, 0x00, 0x00)
    static let bg              = rgb(0x1C, 0x1C, 0x1E)
    static let panel           = rgb(0x2C, 0x2C, 0x2E)
    static let panelHi         = rgb(0x3A, 0x3A, 0x3C)
    static let rule            = Color(red: 84.0/255, green: 84.0/255, blue: 88.0/255, opacity: 0.65)
    static let ruleHi          = Color(red: 84.0/255, green: 84.0/255, blue: 88.0/255, opacity: 0.95)

    // MARK: Label hierarchy (dark)
    static let ink             = Color.white
    static let ink2            = Color(red: 235.0/255, green: 235.0/255, blue: 245.0/255, opacity: 0.78)
    static let ink3            = Color(red: 235.0/255, green: 235.0/255, blue: 245.0/255, opacity: 0.60)
    static let ink4            = Color(red: 235.0/255, green: 235.0/255, blue: 245.0/255, opacity: 0.38)

    // MARK: Signal colors (iOS system dark variants)
    static let amber           = rgb(0xFF, 0x9F, 0x0A)
    static let amberDim        = rgb(0xC7, 0x76, 0x00)
    static let cyan            = rgb(0x64, 0xD2, 0xFF)
    static let cyanDim         = rgb(0x3D, 0xA5, 0xCC)
    static let red             = rgb(0xFF, 0x45, 0x3A)
    static let green           = rgb(0x30, 0xD1, 0x58)
    static let blue            = rgb(0x0A, 0x84, 0xFF)

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }
}

/// Font presets. Monospaced readouts use SF Mono via the `.monospaced()` design;
/// display/body use the standard SF Pro (system) stack.
enum CCFont {
    /// Mono "technical readout" — tabular digits, letterSpacing via `.kerning`.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Display — SF Pro Display, tight letterSpacing, used for large titles.
    static func display(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Body sans — SF Pro Text / system default.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
