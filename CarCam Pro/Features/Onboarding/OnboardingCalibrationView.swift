import SwiftUI
import CoreMotion

/// Step 3 — horizon / mount calibration. Live pitch + roll readings from
/// Core Motion drive a rounded "bubble level" target; the user taps
/// continue once the bubble centers.
struct OnboardingCalibrationView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var pitch: Double = 0
    @State private var roll: Double = 0
    @State private var motionManager = CMMotionManager()
    @State private var isLive = false

    private var isLevel: Bool {
        abs(pitch) <= 1.5 && abs(roll) <= 1.5
    }

    var body: some View {
        OnboardingFrame(step: 3) {
            OnboardingTitle(
                eyebrow: "Calibration",
                title: "Level your mount",
                subtitle: "Place the phone in landscape on your windshield and hold it still. The bubble will center when the horizon is level."
            )

            BubbleLevelCard(pitch: pitch, roll: roll, isLevel: isLevel)

            hint
        } footer: {
            OnboardingPrimaryButton(title: isLevel ? "Save & Continue" : "Continue Anyway") {
                stop()
                onContinue()
            }
            OnboardingSecondaryButton(title: "Skip") {
                stop()
                onSkip()
            }
        }
        .task { startMotion() }
        .onDisappear { stop() }
    }

    private var hint: some View {
        HStack(spacing: CCTheme.Space.md) {
            Image(systemName: isLevel ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(isLevel ? CCTheme.green : CCTheme.accent)

            Text(isLevel
                 ? "Looks level. You're good to go."
                 : (roll > 0
                    ? "Rotate the phone counter-clockwise \(String(format: "%.1f", abs(roll)))°"
                    : "Rotate the phone clockwise \(String(format: "%.1f", abs(roll)))°"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(CCTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func startMotion() {
        guard !isLive, motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let m = motion else { return }
            pitch = m.attitude.pitch * 180.0 / .pi
            roll  = m.attitude.roll  * 180.0 / .pi
        }
        isLive = true
    }

    private func stop() {
        guard isLive else { return }
        motionManager.stopDeviceMotionUpdates()
        isLive = false
    }
}

private struct BubbleLevelCard: View {
    let pitch: Double
    let roll: Double
    let isLevel: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    // Target rings
                    Circle()
                        .strokeBorder(Color(.separator), lineWidth: 1)
                        .frame(width: size * 0.75, height: size * 0.75)
                    Circle()
                        .strokeBorder(Color(.separator), lineWidth: 1)
                        .frame(width: size * 0.45, height: size * 0.45)
                    Circle()
                        .strokeBorder(CCTheme.accent.opacity(0.4), lineWidth: 1)
                        .frame(width: size * 0.18, height: size * 0.18)

                    // Crosshair
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: size * 0.75, height: 1)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: size * 0.75)

                    // Bubble
                    Circle()
                        .fill(isLevel ? CCTheme.green : CCTheme.accent)
                        .frame(width: 22, height: 22)
                        .shadow(color: (isLevel ? CCTheme.green : CCTheme.accent).opacity(0.7),
                                radius: 8)
                        .offset(
                            x: clamped(roll, to: -20...20) * (size / 80),
                            y: clamped(pitch, to: -20...20) * (size / 80)
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.8),
                                   value: roll)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8),
                                   value: pitch)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(CCTheme.Space.lg)

            VStack {
                Spacer()
                readouts
                    .padding(CCTheme.Space.md)
            }
        }
        .frame(height: 280)
    }

    private var readouts: some View {
        HStack {
            readoutColumn(label: "Pitch", value: pitch, highlight: false)
            Spacer()
            readoutColumn(label: "Roll", value: roll, highlight: abs(roll) > 1.5)
        }
    }

    private func readoutColumn(label: String, value: Double, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(String(format: "%+.1f°", value))
                .font(CCFont.mono(16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(highlight ? CCTheme.accent : .primary)
        }
    }

    private func clamped(_ v: Double, to range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}
