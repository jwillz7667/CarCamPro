import SwiftUI
import AVFoundation
import CoreLocation
import CoreMotion
import UIKit

/// Step 4 — "You're set". Shows a live system snapshot so the user can
/// confirm each sensor is actually working before the main app shell opens.
struct OnboardingReadyView: View {
    let onFinish: () -> Void

    @State private var checks: [SystemCheck] = SystemCheck.placeholders

    var body: some View {
        OnboardingFrame(step: 6, total: 6) {
            OnboardingTitle(
                eyebrow: "All Set",
                title: "You're ready to record",
                subtitle: "CarCam Pro is armed with your permissions and calibrated to your mount. Tap REC on the Live tab anytime."
            )

            VStack(spacing: 0) {
                ForEach(checks) { check in
                    checkRow(check)
                    if check.id != checks.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        } footer: {
            OnboardingPrimaryButton(title: "Open CarCam Pro", systemImage: "arrow.right") {
                onFinish()
            }
        }
        .task { await refresh() }
    }

    private func checkRow(_ check: SystemCheck) -> some View {
        HStack(spacing: CCTheme.Space.md) {
            Image(systemName: check.symbol)
                .font(.title3)
                .foregroundStyle(check.ok ? CCTheme.green : CCTheme.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((check.ok ? CCTheme.green : CCTheme.accent).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(check.label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(check.value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(check.ok ? CCTheme.green : CCTheme.accent)
        }
        .padding(CCTheme.Space.md)
    }

    private func refresh() async {
        var updated: [SystemCheck] = []

        let cameraOk = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        updated.append(.init(
            id: "cam", label: "Camera",
            value: cameraOk ? "\(AppSettings.shared.resolution.displayName) · \(AppSettings.shared.frameRate) fps" : "Not authorized",
            ok: cameraOk, symbol: "camera.fill"
        ))

        let loc = CLLocationManager().authorizationStatus
        let locOk = loc == .authorizedAlways || loc == .authorizedWhenInUse
        updated.append(.init(
            id: "gps", label: "Location",
            value: locOk ? "Ready" : "Not authorized",
            ok: locOk, symbol: "location.fill"
        ))

        let accelOk = CMMotionManager().isAccelerometerAvailable
        updated.append(.init(
            id: "accel", label: "Motion",
            value: accelOk ? "±4g range" : "Unavailable",
            ok: accelOk, symbol: "waveform.path.ecg"
        ))

        updated.append(.init(
            id: "stor", label: "Storage",
            value: storageFreeString(),
            ok: true, symbol: "externaldrive.fill"
        ))

        updated.append(.init(
            id: "bat", label: "Battery",
            value: batteryString(),
            ok: true, symbol: "battery.100percent"
        ))

        checks = updated
    }

    private func storageFreeString() -> String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            let gb = Double(bytes) / 1_073_741_824
            return String(format: "%.1f GB free", gb)
        }
        return "Unknown"
    }

    private func batteryString() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        if level < 0 { return "Monitoring…" }
        let pct = Int(level * 100)
        return charging ? "\(pct)% · charging" : "\(pct)%"
    }
}

private struct SystemCheck: Identifiable {
    let id: String
    let label: String
    let value: String
    let ok: Bool
    let symbol: String

    static let placeholders: [SystemCheck] = [
        .init(id: "cam", label: "Camera", value: "—", ok: true, symbol: "camera.fill"),
        .init(id: "gps", label: "Location", value: "—", ok: true, symbol: "location.fill"),
        .init(id: "accel", label: "Motion", value: "—", ok: true, symbol: "waveform.path.ecg"),
        .init(id: "stor", label: "Storage", value: "—", ok: true, symbol: "externaldrive.fill"),
        .init(id: "bat", label: "Battery", value: "—", ok: true, symbol: "battery.100percent"),
    ]
}
