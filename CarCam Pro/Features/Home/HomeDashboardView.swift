import SwiftUI
import SwiftData

/// HOME tab — editorial "minimal" variant of the dashboard (see `DashboardMinimal`
/// in the Claude Design handoff). Focuses on this-week telemetry + a prominent
/// REC action. Routes the user into the landscape live HUD on tap.
struct HomeDashboardView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = HomeViewModel()
    @Binding var activeTab: CCTab

    var body: some View {
        ZStack {
            CCTheme.void.ignoresSafeArea()

            VStack(spacing: 0) {
                CCTopBar {
                    CCArmedIndicator(
                        armed: container.recordingEngine.state.isIdle ? false : true,
                        storageFree: storageFreeLabel
                    )
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, 24)
                            .padding(.top, 36)

                        weeklyBlock
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                            .padding(.bottom, 18)

                        quickStatsBlock
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                }

                recordButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .onAppear { viewModel.refresh(context: modelContext) }
    }

    // MARK: - Header block

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            CCLabel("TODAY — \(viewModel.todayDate)", size: 10, color: CCTheme.ink4)

            Text(headline.title)
                .font(CCFont.display(44, weight: .light))
                .kerning(-1.3)
                .foregroundStyle(CCTheme.ink)
                .lineSpacing(-4)

            Text(headline.subtitle)
                .font(CCFont.sans(14))
                .foregroundStyle(CCTheme.ink3)
                .padding(.top, 4)
        }
    }

    private var headline: (title: String, subtitle: String) {
        if container.recordingEngine.state.isRecording {
            return ("Recording\nin progress.", "Tap LIVE to view the dashboard HUD.")
        }
        if let last = viewModel.lastTrip {
            return (
                "Ready to\nrecord.",
                "Last trip ended \(last.minutesAgo) min ago at \(last.endLocation)."
            )
        }
        return ("Ready to\nrecord.", "Drive safely. CarCam is armed and ready.")
    }

    // MARK: - Weekly block

    private var weeklyBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(CCTheme.rule).frame(height: 1)
                .padding(.bottom, 18)

            HStack {
                CCLabel("THIS WEEK", size: 9, color: CCTheme.ink4)
                Spacer()
                CCLabel(deltaLabel, size: 9, color: CCTheme.ink4)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(milesFormatted)
                    .font(CCFont.mono(64, weight: .thin))
                    .kerning(-2.5)
                    .foregroundStyle(CCTheme.ink)
                    .monospacedDigit()
                Text("MI")
                    .font(CCFont.mono(18))
                    .foregroundStyle(CCTheme.ink4)
            }
            .padding(.top, 12)

            Sparkline(bars: viewModel.weeklySummary.dailyMileBars,
                      activeIndex: viewModel.weeklySummary.activeDayIndex)
                .frame(height: 32)
                .padding(.top, 14)

            HStack {
                let dayLetters = ["M","T","W","T","F","S","S"]
                ForEach(Array(dayLetters.enumerated()), id: \.offset) { idx, letter in
                    CCLabel(
                        letter,
                        size: 9,
                        color: idx == viewModel.weeklySummary.activeDayIndex ? CCTheme.amber : CCTheme.ink4
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        }
    }

    private var milesFormatted: String {
        if viewModel.weeklySummary.miles == viewModel.weeklySummary.miles.rounded() {
            return String(format: "%.0f", viewModel.weeklySummary.miles)
        }
        return String(format: "%.1f", viewModel.weeklySummary.miles)
    }

    private var deltaLabel: String {
        let pct = viewModel.weeklySummary.vsLastWeekPct
        if pct == 0 { return "VS LAST WEEK —" }
        return String(format: "%+.0f%% VS LAST", pct)
    }

    // MARK: - Quick stats 2x2

    private var quickStatsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(CCTheme.rule).frame(height: 1)

            let rows: [[(String, String)]] = [
                [("TRIPS", String(viewModel.quickStats.trips)),
                 ("CLIPS LOCKED", String(viewModel.quickStats.clipsLocked))],
                [("TOP SPEED", String(viewModel.quickStats.topSpeedMPH)),
                 ("INCIDENTS", String(viewModel.quickStats.incidents))],
            ]

            ForEach(0..<rows.count, id: \.self) { rowIdx in
                HStack(spacing: 20) {
                    ForEach(0..<rows[rowIdx].count, id: \.self) { colIdx in
                        statCell(label: rows[rowIdx][colIdx].0,
                                 value: rows[rowIdx][colIdx].1)
                    }
                }
                .padding(.vertical, 18)
            }
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CCLabel(label, size: 9, color: CCTheme.ink4)
            Text(value)
                .font(CCFont.mono(28, weight: .light))
                .kerning(-0.5)
                .foregroundStyle(CCTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - REC button

    private var recordButton: some View {
        Button {
            Task {
                if container.recordingEngine.state.isRecording {
                    try? await container.recordingEngine.stopRecording()
                } else {
                    try? await container.recordingEngine.startRecording()
                    activeTab = .live
                }
            }
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(CCTheme.red)
                    .frame(width: 10, height: 10)
                Text(container.recordingEngine.state.isRecording ? "Stop recording" : "Start recording")
                    .font(CCFont.mono(13, weight: .medium))
                    .kerning(3.25)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .foregroundStyle(CCTheme.void)
            .background(CCTheme.amber)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .heavy), trigger: container.recordingEngine.state.isRecording)
    }

    // MARK: - Helpers

    private var storageFreeLabel: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            let gb = Double(bytes) / 1_073_741_824
            return String(format: "%.1f GB", gb)
        }
        return "—"
    }
}

/// 7-bar sparkline. Today's bar is drawn in amber.
private struct Sparkline: View {
    let bars: [Double]
    let activeIndex: Int

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { idx, v in
                    Rectangle()
                        .fill(idx == activeIndex ? CCTheme.amber : CCTheme.ruleHi)
                        .frame(height: max(2, geo.size.height * CGFloat(v) / 30))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }
}
