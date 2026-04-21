import SwiftUI
import SwiftData

/// TRIPS tab — archive of recording sessions. Native `List` with
/// `.insetGrouped` style, a "This Week" summary card at the top, and a
/// sheet-presented incident playback detail view.
struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \RecordingSession.startDate, order: .reverse)
    private var sessions: [RecordingSession]

    @State private var selectedSession: RecordingSession?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if !sessions.isEmpty {
                    summarySection
                }

                if sessions.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 40, leading: 20, bottom: 40, trailing: 20))
                } else {
                    tripsSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Trips")
            .sheet(item: $selectedSession) { session in
                IncidentPlaybackView(session: session)
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        let weekMiles = sessions.prefix(7).reduce(0.0) { $0 + $1.totalDistanceMeters / 1609.344 }
        let weekMinutes = sessions.prefix(7).reduce(0.0) { $0 + $1.totalDuration / 60 }
        let lockedClips = sessions.prefix(7).reduce(0) { $0 + $1.lockedClipCount }

        return Section("This Week") {
            HStack(spacing: CCTheme.Space.md) {
                summaryCell(systemImage: "road.lanes", title: "Distance",
                            value: String(format: "%.1f", weekMiles), unit: "mi")
                summaryCell(systemImage: "clock.fill", title: "Time",
                            value: formatHours(minutes: weekMinutes), unit: "hr")
                summaryCell(systemImage: "lock.fill", title: "Locked",
                            value: "\(lockedClips)", unit: "clips")
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    private func summaryCell(systemImage: String, title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(CCTheme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CCTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusCard, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func formatHours(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m)m" }
        return String(format: "%d:%02d", h, m)
    }

    // MARK: - Trips list

    private var tripsSection: some View {
        Section(sessions.count == 1 ? "1 Session" : "\(sessions.count) Sessions") {
            ForEach(sessions) { session in
                Button {
                    selectedSession = session
                } label: {
                    tripRow(for: session)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tripRow(for session: RecordingSession) -> some View {
        let miles = session.totalDistanceMeters / 1609.344
        let minutes = Int(session.totalDuration / 60)
        let avgMPH = session.totalDuration > 0
            ? miles / (session.totalDuration / 3600)
            : 0

        return HStack(spacing: CCTheme.Space.md) {
            Image(systemName: session.lockedClipCount > 0 ? "lock.fill" : "car.fill")
                .font(.title3)
                .foregroundStyle(session.lockedClipCount > 0 ? CCTheme.red : CCTheme.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((session.lockedClipCount > 0 ? CCTheme.red : CCTheme.accent).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.routeLabel ?? Self.dayFormatter.string(from: session.startDate))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(String(format: "%.1f mi · %d min · %d mph avg",
                            miles, minutes, Int(avgMPH.rounded())))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if session.lockedClipCount > 0 {
                Text("\(session.lockedClipCount)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(CCTheme.red.opacity(0.15))
                    )
                    .foregroundStyle(CCTheme.red)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: CCTheme.Space.md) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No trips yet")
                .font(.title3.weight(.semibold))
            Text("Start a recording from the Live tab. Sessions appear here automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
