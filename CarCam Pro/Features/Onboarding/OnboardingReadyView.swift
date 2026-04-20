import SwiftUI
import CoreLocation
import CoreMotion
import AVFoundation

/// Step 4 — "All systems nominal." Does a quick real-system check and renders
/// a mini-diagnostic log, then hands off to the main app shell.
struct OnboardingReadyView: View {
    let onFinish: () -> Void

    @State private var checks: [SystemCheck] = SystemCheck.placeholders

    var body: some View {
        OnboardingFrame(step: 4) {
            VStack(alignment: .leading, spacing: 0) {
                CCLabel("04 — System ready", size: 10, color: CCTheme.green)
                    .padding(.bottom, 8)

                Text("All systems\nnominal.")
                    .font(CCFont.display(36, weight: .light))
                    .kerning(-0.7)
                    .foregroundStyle(CCTheme.ink)
                    .padding(.bottom, 32)

                VStack(spacing: 0) {
                    Rectangle().fill(CCTheme.rule).frame(height: 1)
                    ForEach(checks) { check in
                        checkRow(check)
                        Rectangle().fill(CCTheme.rule).frame(height: 1)
                    }
                }
                .padding(.bottom, 24)

                diagnostic
                    .padding(.bottom, 16)

                Spacer()

                OnboardingButton(title: "Start recording", primary: true) {
                    onFinish()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 110)
            .padding(.bottom, 90)
        }
        .task { await refreshChecks() }
    }

    // MARK: - Rows

    private func checkRow(_ check: SystemCheck) -> some View {
        HStack(spacing: 12) {
            Text("●")
                .foregroundStyle(check.ok ? CCTheme.green : CCTheme.amber)
                .font(CCFont.mono(12))

            Text(check.label)
                .font(CCFont.mono(12))
                .foregroundStyle(CCTheme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(check.value)
                .font(CCFont.mono(12))
                .foregroundStyle(CCTheme.ink)
        }
        .padding(.vertical, 12)
    }

    private var diagnostic: some View {
        VStack(alignment: .leading, spacing: 4) {
            diagLine("handshake.sensor_bus", "OK", color: CCTheme.green)
            diagLine("calibrate.horizon", "OK", color: CCTheme.green)
            diagLine("init.loop_buffer 90min", "OK", color: CCTheme.green)
            diagLine("standby.impact_detect", "ARMED", color: CCTheme.amber)
        }
        .padding(14)
        .background(CCTheme.panel)
        .overlay(Rectangle().stroke(CCTheme.rule, lineWidth: 1))
    }

    private func diagLine(_ key: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("> \(key)")
                .font(CCFont.mono(10))
                .foregroundStyle(CCTheme.ink4)
            Text(String(repeating: ".", count: max(1, 25 - key.count)))
                .font(CCFont.mono(10))
                .foregroundStyle(CCTheme.ink4)
                .lineLimit(1)
            Text(value)
                .font(CCFont.mono(10))
                .foregroundStyle(color)
        }
    }

    // MARK: - Live system snapshot

    private func refreshChecks() async {
        var updated: [SystemCheck] = []
        let cameraOk = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        updated.append(SystemCheck(id: "cam", label: "Camera",
                                   value: cameraOk ? "\(AppSettings.shared.resolution.displayName) / \(AppSettings.shared.frameRate)" : "NOT AUTHORIZED",
                                   ok: cameraOk))

        let loc = CLLocationManager().authorizationStatus
        let locOk = loc == .authorizedAlways || loc == .authorizedWhenInUse
        updated.append(SystemCheck(id: "gps", label: "GPS lock",
                                   value: locOk ? "authorized" : "pending",
                                   ok: locOk))

        let accelOk = CMMotionManager().isAccelerometerAvailable
        updated.append(SystemCheck(id: "accel", label: "Accelerometer",
                                   value: accelOk ? "±4g range" : "N/A",
                                   ok: accelOk))

        let free = storageFreeString()
        updated.append(SystemCheck(id: "stor", label: "Storage",
                                   value: free,
                                   ok: true))

        let battery = batteryString()
        updated.append(SystemCheck(id: "bat", label: "Battery",
                                   value: battery,
                                   ok: true))

        checks = updated
    }

    private func storageFreeString() -> String {
        let url = URL(fileURLWithPath: NSHomeDirectory() as String)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            let gb = Double(bytes) / 1_073_741_824
            return String(format: "%.1f GB free", gb)
        }
        return "unknown"
    }

    private func batteryString() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        if level < 0 { return "monitoring…" }
        let pct = Int(level * 100)
        return charging ? "\(pct)% · charging" : "\(pct)%"
    }
}

private struct SystemCheck: Identifiable {
    let id: String
    let label: String
    let value: String
    let ok: Bool

    static let placeholders: [SystemCheck] = [
        SystemCheck(id: "cam", label: "Camera", value: "…", ok: true),
        SystemCheck(id: "gps", label: "GPS lock", value: "…", ok: true),
        SystemCheck(id: "accel", label: "Accelerometer", value: "…", ok: true),
        SystemCheck(id: "stor", label: "Storage", value: "…", ok: true),
        SystemCheck(id: "bat", label: "Battery", value: "…", ok: true),
    ]
}
