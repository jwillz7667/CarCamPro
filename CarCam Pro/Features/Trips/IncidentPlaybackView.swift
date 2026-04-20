import SwiftUI
import SwiftData
import AVKit
import OSLog

/// Trip detail / incident playback — shows the locked clip with scrubber,
/// telemetry trace, stat strip, and Share/Export/Generate Report actions.
struct IncidentPlaybackView: View {
    let session: RecordingSession

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var selectedClip: VideoClip?

    private var clips: [VideoClip] {
        session.clips.sorted { $0.startDate < $1.startDate }
    }

    private var headlineClip: VideoClip? {
        clips.first(where: { $0.isProtected }) ?? clips.first
    }

    var body: some View {
        ZStack {
            CCTheme.void.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 56)

                header
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 14)

                videoWindow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                telemetryTrace
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                statStrip

                Spacer()

                actions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { loadFirstClip() }
        .onDisappear { player?.pause() }
    }

    // MARK: - Top bar / header

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    CCLabel("BACK", size: 10, color: CCTheme.ink3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(CCTheme.ink3)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                CCRecDot(size: 6, color: CCTheme.red)
                CCLabel("LOCKED", size: 9, color: CCTheme.red)
            }
            .padding(.trailing, 20)
        }
    }

    private var header: some View {
        let peakG = clips.compactMap(\.peakGForce).max() ?? session.peakSpeedMPH
        let title = "Impact event — \(String(format: "%.1f", peakG))g"
        let stamp = formattedTimestamp

        return VStack(alignment: .leading, spacing: 6) {
            CCLabel("INCIDENT · LOCKED CLIP", size: 9, color: CCTheme.red)
            Text(title)
                .font(CCFont.display(24, weight: .light))
                .kerning(-0.4)
                .foregroundStyle(CCTheme.ink)
            Text(stamp)
                .font(CCFont.mono(11))
                .foregroundStyle(CCTheme.ink3)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Video window

    private var videoWindow: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(CCCrosshair(color: CCTheme.red))
            } else {
                CCFeedPlaceholder(label: headlineClip.map { "CLIP \($0.fileName) · \($0.formattedDuration)" } ?? "NO CLIP") {
                    CCCrosshair(color: CCTheme.red)
                }
                .aspectRatio(16/9, contentMode: .fit)
            }

            VStack {
                HStack {
                    HStack(spacing: 10) {
                        CCRecDot(size: 6, color: CCTheme.red)
                        CCLabel("REVIEW · 0.5×", size: 9, color: CCTheme.red)
                    }
                    Spacer()
                    if let clip = headlineClip {
                        Text(clip.formattedDuration)
                            .font(CCFont.mono(11))
                            .foregroundStyle(CCTheme.ink)
                    }
                }
                Spacer()
            }
            .padding(10)
        }
        .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
    }

    // MARK: - Telemetry trace

    private var telemetryTrace: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CCLabel("TELEMETRY — G-FORCE", size: 9, color: CCTheme.ink3)
                Spacer()
                if let peakG = clips.compactMap(\.peakGForce).max() {
                    CCLabel(String(format: "PEAK %.2fg", peakG),
                            size: 9, color: CCTheme.red)
                }
            }
            TelemetryTraceView(samples: syntheticTrace(from: clips))
                .frame(height: 60)
                .background(CCTheme.bg)
                .overlay(Rectangle().stroke(CCTheme.rule, lineWidth: 1))
        }
    }

    // MARK: - Stat strip

    private var statStrip: some View {
        HStack(spacing: 1) {
            statCell(label: "SPEED",
                     value: String(Int(session.peakSpeedMPH.rounded())),
                     unit: "MPH")
            statCell(label: "PEAK G",
                     value: String(format: "%.2f", clips.compactMap(\.peakGForce).max() ?? 0),
                     unit: "G",
                     tint: CCTheme.red)
            statCell(label: "TRIPS",
                     value: "01",
                     unit: nil)
            statCell(label: "CLIPS",
                     value: String(clips.count),
                     unit: nil)
        }
        .background(CCTheme.rule)
        .overlay(alignment: .top) { Rectangle().fill(CCTheme.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(CCTheme.rule).frame(height: 1) }
    }

    private func statCell(label: String, value: String, unit: String?, tint: Color = CCTheme.ink) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            CCLabel(label, size: 8, color: CCTheme.ink4)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(CCFont.mono(15))
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(CCFont.mono(8))
                        .foregroundStyle(CCTheme.ink4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CCTheme.bg)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            actionButton("SHARE", flex: 1) { share() }
            actionButton("EXPORT .MP4", flex: 1) { exportClip() }
            actionButton("GENERATE REPORT", flex: 1.3, primary: true) { generateReport() }
        }
    }

    private func actionButton(_ title: String,
                              flex: CGFloat,
                              primary: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CCFont.mono(10, weight: .medium))
                .kerning(2.0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(primary ? CCTheme.void : CCTheme.ink)
                .background(primary ? CCTheme.amber : Color.clear)
                .overlay(Rectangle().stroke(primary ? .clear : CCTheme.ruleHi, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func loadFirstClip() {
        guard let clip = headlineClip else { return }
        selectedClip = clip
        let url = clip.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        player = AVPlayer(url: url)
    }

    private var formattedTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM · HH:mm:ss"
        let date = f.string(from: session.startDate).uppercased()
        if let road = session.routeLabel {
            return "\(date) · \(road)"
        }
        return "\(date) · SESSION \(session.shortID.uppercased())"
    }

    private func syntheticTrace(from clips: [VideoClip]) -> [Double] {
        // Use peakGForce from clips as sparse samples — pad to 32 points.
        let points = clips.compactMap(\.peakGForce)
        if points.isEmpty { return Array(repeating: 0.0, count: 32) }
        var result = [Double]()
        for i in 0..<32 {
            let idx = Int(Double(i) * Double(points.count - 1) / 31.0)
            result.append(points[max(0, min(points.count - 1, idx))])
        }
        return result
    }

    private func share() {
        guard let url = selectedClip?.fileURL else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(av, animated: true)
    }

    private func exportClip() { share() }

    private func generateReport() {
        // Report generation stub — future ticket will render a PDF.
        AppLogger.ui.info("Generate-report invoked for session \(session.shortID)")
    }
}

/// Line chart for a sparse array of g-force samples. Peak marker drawn in red.
struct TelemetryTraceView: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // Horizontal grid lines.
                for y in [size.height * 0.25, size.height * 0.5, size.height * 0.75] {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(CCTheme.rule), lineWidth: 1)
                }

                guard samples.count > 1, let peak = samples.max(), peak > 0 else { return }
                let step = size.width / CGFloat(samples.count - 1)
                var path = Path()
                for (i, v) in samples.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height - (CGFloat(v / peak) * size.height * 0.9) - 3
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else     { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(CCTheme.amber), lineWidth: 1.5)

                // Peak marker (vertical dashed line + dot).
                if let idx = samples.firstIndex(of: peak) {
                    let px = CGFloat(idx) * step
                    var ln = Path()
                    ln.move(to: CGPoint(x: px, y: 0))
                    ln.addLine(to: CGPoint(x: px, y: size.height))
                    ctx.stroke(ln, with: .color(CCTheme.red), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                    let r: CGFloat = 3
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - r, y: 3, width: r * 2, height: r * 2)),
                        with: .color(CCTheme.red)
                    )
                }
            }
        }
    }
}
