import SwiftUI
import SwiftData

/// TRIPS tab — archive of recording sessions with per-day grouping, weekly
/// summary strip, and tap-through to the incident playback screen.
struct TripsListView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \RecordingSession.startDate, order: .reverse)
    private var sessions: [RecordingSession]

    @State private var selectedSession: RecordingSession?
    @Binding var activeTab: CCTab

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()

    var body: some View {
        ZStack {
            CCTheme.void.ignoresSafeArea()

            VStack(spacing: 0) {
                CCTopBar {
                    CCLabel("\(sessions.count) THIS WEEK", size: 9, color: CCTheme.ink3)
                }

                header
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                summaryStrip

                ScrollView {
                    LazyVStack(spacing: 0) {
                        Rectangle().fill(CCTheme.rule).frame(height: 1)
                        ForEach(sessions) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                tripRow(for: session)
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(CCTheme.rule).frame(height: 1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .sheet(item: $selectedSession) { session in
            IncidentPlaybackView(session: session)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            CCLabel("ARCHIVE / SESSIONS", size: 9, color: CCTheme.ink4)
            Text("Trips")
                .font(CCFont.display(32, weight: .light))
                .kerning(-0.6)
                .foregroundStyle(CCTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary strip (3 columns)

    private var summaryStrip: some View {
        let weekMiles = sessions.prefix(7).reduce(0) { $0 + $1.totalDistanceMeters / 1609.344 }
        let weekMinutes = sessions.prefix(7).reduce(0) { $0 + $1.totalDuration / 60 }
        let lockedClips = sessions.prefix(7).reduce(0) { $0 + $1.lockedClipCount }

        return HStack(spacing: 1) {
            summaryCell(label: "TOTAL",
                        value: String(format: "%.1f", weekMiles),
                        unit: "MI")
            summaryCell(label: "TIME",
                        value: formattedHours(minutes: weekMinutes),
                        unit: "HR")
            summaryCell(label: "LOCKED",
                        value: String(lockedClips),
                        unit: "CLIPS")
        }
        .background(CCTheme.rule)
        .overlay(alignment: .top) { Rectangle().fill(CCTheme.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(CCTheme.rule).frame(height: 1) }
    }

    private func summaryCell(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CCLabel(label, size: 8, color: CCTheme.ink4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(CCFont.mono(20, weight: .light))
                    .foregroundStyle(CCTheme.ink)
                CCLabel(unit, size: 9, color: CCTheme.ink4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CCTheme.bg)
    }

    private func formattedHours(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Row

    private func tripRow(for session: RecordingSession) -> some View {
        let miles = session.totalDistanceMeters / 1609.344
        let minutes = Int(session.totalDuration / 60)
        let avgMPH = session.totalDuration > 0
            ? miles / (session.totalDuration / 3600)
            : 0
        let stats = String(format: "%.1f MI · %d MIN · AVG %d MPH",
                           miles, minutes, Int(avgMPH.rounded()))

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayFormatter.string(from: session.startDate))
                    .font(CCFont.mono(22, weight: .light))
                    .foregroundStyle(CCTheme.ink)
                CCLabel(monthFormatter.string(from: session.startDate),
                        size: 9,
                        color: CCTheme.ink4)
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.routeLabel ?? "Trip · \(session.shortID)")
                    .font(CCFont.sans(15))
                    .foregroundStyle(CCTheme.ink)
                Text(stats)
                    .font(CCFont.mono(10))
                    .foregroundStyle(CCTheme.ink3)
                    .kerning(0.8)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if session.lockedClipCount > 0 {
                    Text("◉ \(session.lockedClipCount)")
                        .font(CCFont.mono(9, weight: .medium))
                        .kerning(1.4)
                        .foregroundStyle(CCTheme.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().stroke(CCTheme.red, lineWidth: 1))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(CCTheme.ink4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(CCTheme.void)
    }
}
