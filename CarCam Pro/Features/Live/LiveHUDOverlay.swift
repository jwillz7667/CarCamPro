import SwiftUI

/// The HUD floating on top of the camera preview.
///
/// Layout (landscape):
///  - top row:    REC stamp + timecode  ·  coordinate + road
///  - left col:   big velocity gauge
///  - center:     AR horizon bracket
///  - right col:  stacked G-force target + heading/altitude
///  - bottom row: loop-buffer timeline + LOCK/STOP buttons
struct LiveHUDOverlay: View {
    let hud: LiveHUDState
    let isRecording: Bool
    let duration: String
    let onLock: () -> Void
    let onStop: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                topBar
                    .padding(.top, 14)
                    .padding(.horizontal, 22)

                HStack(alignment: .center, spacing: 0) {
                    leftCluster
                        .padding(.leading, 22)
                    Spacer()
                    rightCluster
                        .padding(.trailing, 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                centerReticle
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    Spacer()
                    bottomBar
                        .padding(.horizontal, 22)
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(true)
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .top) {
            recStamp
            Spacer()
            locationStamp
        }
    }

    private var recStamp: some View {
        HStack(spacing: 10) {
            CCRecDot(size: 8, color: isRecording ? CCTheme.red : CCTheme.ink4)
            CCLabel(isRecording ? "REC" : "STANDBY", size: 10,
                    color: isRecording ? CCTheme.red : CCTheme.ink4)
            Rectangle().fill(CCTheme.ruleHi).frame(width: 1, height: 12)
            Text(duration)
                .font(CCFont.mono(13))
                .monospacedDigit()
                .foregroundStyle(CCTheme.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55))
        .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
    }

    private var locationStamp: some View {
        VStack(alignment: .trailing, spacing: 4) {
            CCLabel(hud.coordinateLabel, size: 9, color: CCTheme.ink3)
            if !hud.roadLabel.isEmpty {
                CCLabel(hud.roadLabel, size: 9, color: CCTheme.ink3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55))
        .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
    }

    // MARK: - Clusters

    private var leftCluster: some View {
        CCPanel(padding: 14) {
            ZStack {
                CCCrosshair(color: CCTheme.ink4, size: 6)
                CCGauge(
                    value: hud.speedMPH,
                    maxValue: 120,
                    size: 150,
                    label: "VELOCITY",
                    unit: "MPH",
                    sublabel: "LIMIT \(hud.speedLimitMPH)"
                )
            }
        }
    }

    private var rightCluster: some View {
        VStack(spacing: 12) {
            CCPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        CCLabel("G-FORCE", size: 9, color: CCTheme.ink4)
                        Spacer()
                        CCLabel(String(format: "PEAK %.1f", hud.peakG),
                                size: 9, color: CCTheme.cyan)
                    }

                    GForceTarget(x: hud.gAxisX, y: hud.gAxisY)
                        .frame(width: 150, height: 150)

                    HStack {
                        Text(String(format: "X %+.2f", hud.gAxisX))
                            .font(CCFont.mono(10))
                            .foregroundStyle(CCTheme.cyan)
                        Spacer()
                        Text(String(format: "Y %+.2f", hud.gAxisY))
                            .font(CCFont.mono(10))
                            .foregroundStyle(CCTheme.cyan)
                    }
                }
                .frame(width: 160)
            }

            CCPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        CCLabel("HEADING", size: 9, color: CCTheme.ink4)
                        Spacer()
                        CCLabel("ALT", size: 9, color: CCTheme.ink4)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%03d", Int(hud.heading)))
                            .font(CCFont.mono(22, weight: .light))
                            .foregroundStyle(CCTheme.ink)
                        Text(hud.compass)
                            .font(CCFont.mono(10))
                            .foregroundStyle(CCTheme.ink4)
                        Spacer()
                        Text(String(hud.altitudeFeet))
                            .font(CCFont.mono(14))
                            .foregroundStyle(CCTheme.ink2)
                        Text("FT")
                            .font(CCFont.mono(9))
                            .foregroundStyle(CCTheme.ink4)
                    }
                }
                .frame(width: 160)
            }
        }
    }

    // MARK: - Center reticle

    private var centerReticle: some View {
        VStack(spacing: 4) {
            CCLabel("◆ LVL", size: 10, color: CCTheme.amber)
            ZStack {
                Rectangle()
                    .fill(CCTheme.amber)
                    .opacity(0.4)
                    .frame(width: 120, height: 1)
                HStack {
                    Rectangle().fill(CCTheme.amber).frame(width: 1, height: 8)
                    Spacer()
                    Rectangle().fill(CCTheme.amber).frame(width: 1, height: 8)
                }
                .frame(width: 40)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            CCPanel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        CCLabel("LOOP BUFFER · 90 MIN", size: 9, color: CCTheme.ink3)
                        Spacer()
                        CCLabel(
                            "\(mmss(hud.currentBufferSeconds)) / \(mmss(hud.loopBufferSeconds))",
                            size: 9,
                            color: CCTheme.amber
                        )
                    }
                    bufferTrack
                        .frame(height: 6)
                }
            }

            actionButton(title: "LOCK",
                         icon: Image(systemName: "lock.fill"),
                         accent: CCTheme.amber,
                         filled: false,
                         action: onLock)

            actionButton(title: "STOP",
                         icon: nil,
                         accent: CCTheme.red,
                         filled: true,
                         action: onStop)
        }
    }

    private var bufferTrack: some View {
        GeometryReader { geo in
            let progress = CGFloat(min(1, hud.currentBufferSeconds / max(1, hud.loopBufferSeconds)))
            ZStack(alignment: .leading) {
                Rectangle().fill(CCTheme.rule)
                Rectangle().fill(CCTheme.amber).frame(width: geo.size.width * progress)

                // locked-clip markers
                ForEach(Array(hud.lockedMarkers.enumerated()), id: \.offset) { _, t in
                    Rectangle()
                        .fill(CCTheme.red)
                        .frame(width: 2, height: 10)
                        .offset(x: geo.size.width * CGFloat(t) - 1, y: -2)
                }
            }
        }
    }

    private func actionButton(
        title: String,
        icon: Image?,
        accent: Color,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    icon
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(filled ? CCTheme.ink : accent)
                } else {
                    Rectangle()
                        .fill(filled ? CCTheme.ink : accent)
                        .frame(width: 10, height: 10)
                }
                Text(title)
                    .font(CCFont.mono(11, weight: .medium))
                    .kerning(2.2)
                    .foregroundStyle(filled ? CCTheme.ink : accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(filled ? accent : Color.clear)
            .overlay(Rectangle().stroke(accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: filled ? .heavy : .medium), trigger: title)
    }

    private func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// The G-force bullseye — concentric rings + crosshair + indicator dot.
private struct GForceTarget: View {
    let x: Double
    let y: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach([1.0, 0.66, 0.33], id: \.self) { r in
                    Circle()
                        .stroke(CCTheme.rule, lineWidth: 1)
                        .frame(width: size * r, height: size * r)
                }

                Rectangle().fill(CCTheme.rule).frame(width: 1, height: size)
                Rectangle().fill(CCTheme.rule).frame(width: size, height: 1)

                Circle()
                    .fill(CCTheme.cyan)
                    .frame(width: 6, height: 6)
                    .shadow(color: CCTheme.cyan, radius: 5)
                    .offset(
                        x: CGFloat(max(-1, min(1, x))) * size / 3,
                        y: CGFloat(max(-1, min(1, y))) * size / 3
                    )
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
