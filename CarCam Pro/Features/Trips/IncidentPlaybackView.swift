import SwiftUI
import SwiftData
import AVKit
import OSLog

/// Trip detail / incident playback.
///
/// Presented as a sheet from the Trips list. Uses NavigationStack + a
/// standard iOS close button. The video lives in a rounded-corner container
/// and the telemetry + stats are rendered with native Labels / GroupBoxes.
struct IncidentPlaybackView: View {
    let session: RecordingSession

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var selectedClip: VideoClip?
    @State private var showShare = false

    private var clips: [VideoClip] {
        session.clips.sorted { $0.startDate < $1.startDate }
    }

    private var headlineClip: VideoClip? {
        clips.first(where: { $0.isProtected }) ?? clips.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CCTheme.Space.lg) {
                    headerCard
                    videoCard
                    telemetryCard
                    statsGrid
                    actionsRow
                }
                .padding(.horizontal, CCTheme.Space.lg)
                .padding(.vertical, CCTheme.Space.md)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(session.routeLabel ?? "Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { loadFirstClip() }
        .onDisappear { player?.pause() }
        .sheet(isPresented: $showShare) {
            if let url = selectedClip?.fileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        let peakG = clips.compactMap(\.peakGForce).max() ?? 0
        let hasIncident = clips.contains(where: \.isProtected)

        return HStack(spacing: CCTheme.Space.md) {
            Image(systemName: hasIncident ? "exclamationmark.triangle.fill" : "car.fill")
                .font(.title)
                .foregroundStyle(hasIncident ? CCTheme.red : CCTheme.accent)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: CCTheme.radiusCard, style: .continuous)
                        .fill((hasIncident ? CCTheme.red : CCTheme.accent).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(hasIncident
                     ? String(format: "Impact event — %.1fg", peakG)
                     : "Routine trip")
                    .font(.title3.weight(.semibold))
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(CCTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Video

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    emptyVideo
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous))
        }
    }

    private var emptyVideo: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: "video.slash.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Clip unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Telemetry

    private var telemetryCard: some View {
        let peak = clips.compactMap(\.peakGForce).max() ?? 0
        return GroupBox {
            VStack(alignment: .leading, spacing: CCTheme.Space.sm) {
                HStack {
                    Label("G-Force", systemImage: "waveform.path.ecg")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(String(format: "Peak %.2fg", peak))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(peak >= 1.5 ? CCTheme.red : .primary)
                }

                TelemetryTraceView(samples: samples)
                    .frame(height: 72)
            }
        }
        .groupBoxStyle(.automatic)
    }

    private var samples: [Double] {
        let points = clips.compactMap(\.peakGForce)
        if points.isEmpty { return Array(repeating: 0.0, count: 32) }
        var result = [Double]()
        for i in 0..<32 {
            let idx = Int(Double(i) * Double(points.count - 1) / 31.0)
            result.append(points[max(0, min(points.count - 1, idx))])
        }
        return result
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: CCTheme.Space.md) {
            statTile(icon: "speedometer", label: "Top Speed",
                     value: "\(Int(session.peakSpeedMPH.rounded()))", unit: "mph")
            statTile(icon: "road.lanes", label: "Distance",
                     value: String(format: "%.1f", session.totalDistanceMeters / 1609.344),
                     unit: "mi")
            statTile(icon: "clock.fill", label: "Duration",
                     value: formatDuration(session.totalDuration),
                     unit: "")
            statTile(icon: "film.fill", label: "Clips",
                     value: "\(clips.count)", unit: "")
        }
    }

    private func statTile(icon: String, label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(CCTheme.accent)
                .font(.subheadline)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CCTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusCard, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return String(format: "%d:%02d", h, m) }
        return "\(m)m"
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: CCTheme.Space.md) {
            Button {
                showShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: CCTheme.radiusButton))

            Button {
                generateReport()
            } label: {
                Label("Report", systemImage: "doc.text.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(CCTheme.accent)
            .buttonBorderShape(.roundedRectangle(radius: CCTheme.radiusButton))
        }
    }

    // MARK: - Helpers

    private func loadFirstClip() {
        guard let clip = headlineClip else { return }
        selectedClip = clip
        let url = clip.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        player = AVPlayer(url: url)
    }

    private func generateReport() {
        AppLogger.ui.info("Generate-report invoked for session \(session.shortID)")
    }
}

// MARK: - Telemetry trace

struct TelemetryTraceView: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // Grid lines.
                for y in [size.height * 0.25, size.height * 0.5, size.height * 0.75] {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(Color(.separator).opacity(0.5)),
                               style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                }

                guard samples.count > 1, let peak = samples.max(), peak > 0 else { return }
                let step = size.width / CGFloat(samples.count - 1)

                var fill = Path()
                fill.move(to: CGPoint(x: 0, y: size.height))
                for (i, v) in samples.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height - (CGFloat(v / peak) * size.height * 0.9) - 3
                    fill.addLine(to: CGPoint(x: x, y: y))
                }
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .linearGradient(
                    Gradient(colors: [CCTheme.accent.opacity(0.4), CCTheme.accent.opacity(0.05)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))

                var stroke = Path()
                for (i, v) in samples.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height - (CGFloat(v / peak) * size.height * 0.9) - 3
                    if i == 0 { stroke.move(to: CGPoint(x: x, y: y)) }
                    else      { stroke.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(stroke, with: .color(CCTheme.accent),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Share sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
