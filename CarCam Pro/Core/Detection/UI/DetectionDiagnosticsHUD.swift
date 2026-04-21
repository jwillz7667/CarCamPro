import SwiftUI
import Combine

/// Compact field-facing HUD for the on-device ML detection pipeline.
///
/// Purpose: let QA, beta users, and the engineer sitting in the passenger
/// seat answer "is detection actually running?" at a glance, without waiting
/// for a real cruiser to appear on camera. Everything exposed here maps
/// directly to a counter or timestamp in `DetectionTelemetry`:
///
///   • Top row — health dot (green = processing, amber = stalled, gray =
///     idle) + effective FPS + last-assessment age.
///   • Counters row — received / processed / dropped-thermal / dropped-busy.
///   • Latency row — last + rolling p50 / p95.
///   • Model row — per-model load status (✓ bundled, ⨯ missing).
///   • Active tracks count + last error (if any).
///
/// The HUD is toggled by `AppSettings.showDetectionDiagnostics` — off by
/// default in production; developers flip it on in Settings → Developer.
struct DetectionDiagnosticsHUD: View {
    @State private var telemetry = DetectionTelemetry.shared
    @State private var nowTick: Date = Date()

    /// 1 Hz ticker so the "seconds since last processed" readout counts up
    /// continuously even when the pipeline is silent. Without this, the
    /// view would only redraw on telemetry mutations — exactly the events
    /// we want the user to notice the *absence* of.
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            countersRow
            latencyRow
            modelsRow
            footerRow
        }
        .font(CCFont.mono(11, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, CCTheme.Space.md)
        .padding(.vertical, CCTheme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusCard, style: .continuous)
                .fill(.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: CCTheme.radiusCard, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .onReceive(timer) { nowTick = $0 }
        .accessibilityIdentifier("detection-diagnostics-hud")
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
            Text("ML")
                .font(CCFont.system(10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            Text(healthLabel)
                .font(CCFont.system(10, weight: .semibold))
                .foregroundStyle(healthColor)
            Spacer(minLength: 12)
            Text("\(String(format: "%.1f", telemetry.effectiveFPS)) fps")
                .foregroundStyle(.white)
            Text("·")
                .foregroundStyle(.white.opacity(0.3))
            Text(ageLabel(telemetry.lastAssessmentAt))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var countersRow: some View {
        HStack(spacing: 8) {
            counter("rx", telemetry.framesReceived, tint: CCTheme.cyan)
            counter("ok", telemetry.framesProcessed, tint: CCTheme.green)
            counter("th", telemetry.framesDroppedThermal, tint: CCTheme.amber)
            counter("bu", telemetry.framesDroppedBusy, tint: CCTheme.red)
            Spacer(minLength: 0)
            if telemetry.busyDropRate > 0.05 {
                Text("\(Int(telemetry.busyDropRate * 100))% drop")
                    .foregroundStyle(CCTheme.red)
            }
        }
    }

    private var latencyRow: some View {
        HStack(spacing: 10) {
            latencyCell("last", telemetry.lastInferenceLatencyMs)
            latencyCell("p50", telemetry.rollingP50LatencyMs)
            latencyCell("p95", telemetry.rollingP95LatencyMs)
            Spacer(minLength: 0)
        }
    }

    private var modelsRow: some View {
        HStack(spacing: 10) {
            modelBadge("vehicle", loaded: telemetry.vehicleModelLoaded)
            modelBadge("roof", loaded: telemetry.roofModelLoaded)
            modelBadge("fleet", loaded: telemetry.fleetFeatureModelLoaded)
            Spacer(minLength: 0)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            Text("tracks: \(telemetry.activeTrackCount)")
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            if let err = telemetry.lastError {
                Text(err)
                    .font(CCFont.system(9))
                    .foregroundStyle(CCTheme.red.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: - Cells

    private func counter(_ label: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Text("\(value)").foregroundStyle(tint).monospacedDigit()
        }
    }

    private func latencyCell(_ label: String, _ ms: Double) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Text(ms > 0 ? String(format: "%.0fms", ms) : "—")
                .foregroundStyle(latencyTint(ms))
                .monospacedDigit()
        }
    }

    private func modelBadge(_ label: String, loaded: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: loaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(loaded ? CCTheme.green : CCTheme.red)
            Text(label).foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Styling helpers

    private var healthColor: Color {
        if !telemetry.isHealthy {
            return telemetry.framesReceived > 0 ? CCTheme.amber : .gray
        }
        return CCTheme.green
    }

    private var healthLabel: String {
        if telemetry.framesReceived == 0 { return "idle" }
        if telemetry.isStalled { return "stalled" }
        if telemetry.isHealthy { return "ok" }
        return "warming up"
    }

    private func ageLabel(_ date: Date?) -> String {
        guard let date else { return "never" }
        let s = nowTick.timeIntervalSince(date)
        if s < 1 { return "now" }
        if s < 60 { return "\(Int(s))s ago" }
        return "\(Int(s / 60))m ago"
    }

    private func latencyTint(_ ms: Double) -> Color {
        switch ms {
        case 0: return .white.opacity(0.5)
        case ..<150: return CCTheme.green
        case 150..<400: return CCTheme.amber
        default: return CCTheme.red
        }
    }
}
