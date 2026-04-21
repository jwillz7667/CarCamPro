import SwiftUI
import SwiftData

/// HOME tab — the app's "lock screen". Summarizes armed/idle status,
/// this-week stats, the last trip, and hosts the primary REC floating action.
///
/// Everything lives inside a native `NavigationStack` with an inset-grouped
/// `List`. Cards are rounded rects filled with `systemGroupedBackground`,
/// and the REC button floats as a Liquid Glass pill anchored to the
/// bottom — exactly the pattern Apple uses in Reminders' "New Reminder".
struct HomeDashboardView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    statusSection
                    weeklySection
                    statsSection
                    lastTripSection
                }
                .listStyle(.insetGrouped)
                .contentMargins(.bottom, 120, for: .scrollContent)

                floatingRecordButton
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    armedChip
                }
            }
        }
        .onAppear { viewModel.refresh(context: modelContext) }
    }

    // MARK: - Status section

    private var statusSection: some View {
        Section {
            HStack(spacing: CCTheme.Space.md) {
                Image(systemName: isRecording ? "record.circle.fill" : "checkmark.seal.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(isRecording ? CCTheme.red : CCTheme.green)
                    .symbolEffect(.pulse, options: .repeating, isActive: isRecording)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRecording ? "Recording" : "Armed")
                        .font(.title3.weight(.semibold))
                    Text(isRecording
                         ? "Tap Live to review the HUD"
                         : "Sensors online. CarCam is ready when you are.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Weekly section

    private var weeklySection: some View {
        Section("This Week") {
            VStack(alignment: .leading, spacing: CCTheme.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(milesFormatted)
                        .font(CCFont.rounded(48, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("mi")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    deltaLabel
                }

                Sparkline(bars: viewModel.weeklySummary.dailyMileBars,
                          activeIndex: viewModel.weeklySummary.activeDayIndex)
                    .frame(height: 44)

                dayStrip
            }
            .padding(.vertical, 8)
        }
    }

    private var dayStrip: some View {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return HStack {
            ForEach(Array(letters.enumerated()), id: \.offset) { idx, letter in
                Text(letter)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(idx == viewModel.weeklySummary.activeDayIndex
                                     ? CCTheme.accent : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var deltaLabel: some View {
        let pct = viewModel.weeklySummary.vsLastWeekPct
        let text: String
        let color: Color
        if pct == 0 {
            text = "—"
            color = .secondary
        } else if pct > 0 {
            text = String(format: "+%.0f%%", pct)
            color = CCTheme.green
        } else {
            text = String(format: "%.0f%%", pct)
            color = CCTheme.red
        }
        return Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }

    // MARK: - Stats section

    private var statsSection: some View {
        Section("At a Glance") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: CCTheme.Space.md) {
                statCard(systemImage: "car.fill", label: "Trips", value: String(viewModel.quickStats.trips))
                statCard(systemImage: "lock.fill", label: "Locked", value: String(viewModel.quickStats.clipsLocked))
                statCard(systemImage: "gauge.with.dots.needle.bottom.50percent", label: "Top Speed", value: "\(viewModel.quickStats.topSpeedMPH) mph")
                statCard(systemImage: "exclamationmark.triangle.fill", label: "Incidents", value: String(viewModel.quickStats.incidents))
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    private func statCard(systemImage: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(CCTheme.accent)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CCTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusCard, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Last trip

    @ViewBuilder
    private var lastTripSection: some View {
        if let trip = viewModel.lastTrip {
            Section("Last Trip") {
                HStack(spacing: CCTheme.Space.md) {
                    Image(systemName: "clock.fill")
                        .font(.title3)
                        .foregroundStyle(CCTheme.accent)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ended \(trip.minutesAgo) min ago")
                            .font(.body.weight(.medium))
                        Text(trip.endLocation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Floating REC button

    private var floatingRecordButton: some View {
        HStack {
            Spacer()

            GlassPillButton(
                style: isRecording ? .destructive : .prominent,
                action: toggleRecording
            ) {
                HStack(spacing: 10) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle.fill")
                        .font(.title3)
                    Text(isRecording ? "Stop Recording" : "Start Recording")
                }
            }
            .frame(minWidth: 220)
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)

            Spacer()
        }
        .padding(.bottom, CCTheme.Space.lg)
    }

    // MARK: - Toolbar armed chip

    private var armedChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRecording ? CCTheme.red : CCTheme.green)
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse, options: .repeating, isActive: isRecording)
            Text(isRecording ? "REC" : "Armed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var isRecording: Bool {
        container.recordingEngine.state.isRecording
    }

    private var milesFormatted: String {
        if viewModel.weeklySummary.miles == viewModel.weeklySummary.miles.rounded() {
            return String(format: "%.0f", viewModel.weeklySummary.miles)
        }
        return String(format: "%.1f", viewModel.weeklySummary.miles)
    }

    private func toggleRecording() {
        Task {
            if isRecording {
                try? await container.recordingEngine.stopRecording()
            } else {
                try? await container.recordingEngine.startRecording()
            }
        }
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let bars: [Double]
    let activeIndex: Int

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(bars.enumerated()), id: \.offset) { idx, v in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(idx == activeIndex ? CCTheme.accent : Color(.tertiarySystemFill))
                        .frame(height: max(4, geo.size.height * CGFloat(v) / 30))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }
}
