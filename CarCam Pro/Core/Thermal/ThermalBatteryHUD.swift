import SwiftUI

/// Glass pill exposing the fused thermal + battery tier on LiveCamView.
///
/// Mirrors the detection diagnostics HUD pattern: a tiny, always-glanceable
/// indicator that tells the user *why* quality is being throttled — the
/// #1 cause of dashcam "this app is broken" reviews is drivers not knowing
/// their phone was thermally limited and seeing unexpected 720p clips.
///
/// Rendered as a single row: a colored dot + tier label + supporting
/// signals (raw thermal state, battery %, charging + LPM glyphs).
struct ThermalBatteryHUD: View {
    @State private var thermal: ThermalMonitor
    @State private var battery: BatteryMonitor

    init(thermal: ThermalMonitor, battery: BatteryMonitor) {
        _thermal = State(initialValue: thermal)
        _battery = State(initialValue: battery)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(thermal.effectiveTier.color)
                .frame(width: 8, height: 8)

            Text(thermal.effectiveTier.label)
                .font(CCFont.system(11, weight: .bold))
                .foregroundStyle(.white)

            Text("·").foregroundStyle(.white.opacity(0.3))

            // Raw thermal from ProcessInfo — useful to see when the device
            // is physically hot vs. the battery is what's forcing the tier.
            HStack(spacing: 2) {
                Image(systemName: thermometerIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(thermal.currentTier.label.prefix(4).capitalized)
                    .font(CCFont.mono(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Text("·").foregroundStyle(.white.opacity(0.3))

            // Battery row — shows level, charging bolt, LPM leaf.
            HStack(spacing: 2) {
                Image(systemName: battery.state == .charging ? "bolt.fill" : "battery.100")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(battery.state == .charging ? CCTheme.green : .white.opacity(0.75))
                Text(batteryLabel)
                    .font(CCFont.mono(11, weight: .medium))
                    .foregroundStyle(batteryLevelTint)
                if battery.isLowPowerMode {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CCTheme.amber)
                }
            }
        }
        .padding(.horizontal, CCTheme.Space.md)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.55))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .accessibilityIdentifier("thermal-battery-hud")
    }

    private var thermometerIcon: String {
        switch thermal.currentTier {
        case .nominal:  return "thermometer.low"
        case .fair:     return "thermometer.medium"
        case .serious:  return "thermometer.high"
        case .critical: return "thermometer.variable.and.figure"
        }
    }

    private var batteryLabel: String {
        // level is -1 on simulator / iPads without a battery.
        guard battery.level >= 0 else { return "—" }
        return "\(Int((battery.level * 100).rounded()))%"
    }

    private var batteryLevelTint: Color {
        switch battery.currentTier {
        case .nominal:  return .white.opacity(0.9)
        case .fair:     return CCTheme.amber
        case .serious:  return CCTheme.red
        case .critical: return CCTheme.red
        }
    }
}
