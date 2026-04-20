import SwiftUI
import CoreMotion

/// Step 3 — horizon / mount calibration. Shows live pitch + roll from
/// Core Motion; user taps Save once the indicators read ~0°.
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
            VStack(alignment: .leading, spacing: 0) {
                CCLabel("03 — Calibration", size: 10, color: CCTheme.amber)
                    .padding(.bottom, 8)

                Text("Level your mount.")
                    .font(CCFont.display(30, weight: .light))
                    .kerning(-0.6)
                    .foregroundStyle(CCTheme.ink)
                    .padding(.bottom, 12)

                Text("Place phone in landscape on the windshield. Hold still.")
                    .font(CCFont.sans(13))
                    .foregroundStyle(CCTheme.ink3)
                    .padding(.bottom, 28)

                HorizonCalibrator(
                    pitch: pitch,
                    roll: roll,
                    adjusting: !isLevel
                )
                .aspectRatio(1, contentMode: .fit)

                guidanceHint
                    .padding(.top, 24)

                Spacer(minLength: 24)

                OnboardingButton(title: "Save calibration", primary: true) {
                    stop()
                    onContinue()
                }

                OnboardingButton(title: "Skip for now") {
                    stop()
                    onSkip()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 110)
            .padding(.bottom, 90)
        }
        .task { startMotion() }
        .onDisappear { stop() }
    }

    // MARK: - Motion loop

    private func startMotion() {
        guard !isLive, motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let m = motion else { return }
            // attitude.pitch / .roll are in radians — convert to degrees.
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

    // MARK: - Hint

    private var guidanceHint: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(CCTheme.amber).frame(width: 2)
            let rollMsg = roll > 0 ? "COUNTER-CLOCKWISE" : "CLOCKWISE"
            let message = isLevel
                ? "HORIZON LEVEL. MOUNT READY."
                : "ROTATE PHONE \(rollMsg) \(String(format: "%.1f", abs(roll)))° TO LEVEL HORIZON."
            Text(message)
                .font(CCFont.mono(11, weight: .regular))
                .kerning(0.8)
                .foregroundStyle(CCTheme.ink2)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
    }
}

/// Horizon + bubble level widget driven by live pitch/roll values.
struct HorizonCalibrator: View {
    let pitch: Double
    let roll: Double
    let adjusting: Bool

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // Outer rect + crosshair
                Rectangle().stroke(CCTheme.rule, lineWidth: 1)

                Circle()
                    .fill(RadialGradient(
                        colors: [CCTheme.panelHi, CCTheme.void],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.5
                    ))
                    .frame(width: size, height: size)

                CCCrosshair(color: CCTheme.amber, size: 14)

                // grid
                Rectangle().fill(CCTheme.rule).frame(height: 1)
                Rectangle().fill(CCTheme.rule).frame(width: 1)

                // Tilted horizon
                Rectangle()
                    .fill(CCTheme.amber)
                    .frame(width: size * 0.8, height: 1)
                    .rotationEffect(.degrees(-roll))

                // Bubble level
                Circle()
                    .stroke(CCTheme.amber, lineWidth: 1)
                    .frame(width: 28, height: 28)
                    .shadow(color: CCTheme.amber.opacity(0.7), radius: 6)
                    .offset(
                        x: clamped(roll, to: -20...20) * (size / 60),
                        y: clamped(pitch, to: -20...20) * (size / 60)
                    )

                // Angle readouts
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        axisReadout(label: "PITCH", value: pitch, color: CCTheme.ink)
                            .padding(.trailing, 16)
                        axisReadout(label: "ROLL", value: roll,
                                    color: abs(roll) > 1.5 ? CCTheme.amber : CCTheme.ink)
                        Spacer()
                        CCLabel(adjusting ? "ADJUSTING…" : "READY",
                                size: 9,
                                color: adjusting ? CCTheme.amber : CCTheme.green)
                    }
                    .padding(12)
                }
            }
        }
    }

    private func clamped(_ v: Double, to range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }

    private func axisReadout(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CCLabel(label, size: 9, color: CCTheme.ink4)
            Text(String(format: "%+.1f°", value))
                .font(CCFont.mono(16, weight: .regular))
                .foregroundStyle(color)
        }
    }
}
