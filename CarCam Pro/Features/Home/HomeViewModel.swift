import Foundation
import SwiftData
import SwiftUI

/// Dashboard view model — aggregates this-week summary + last-trip info from
/// SwiftData. Purely read-only; mutations live in `RecordingEngine` and
/// `StorageManager`.
@Observable
@MainActor
final class HomeViewModel {
    struct WeeklySummary: Equatable {
        var miles: Double
        var vsLastWeekPct: Double
        /// Bar heights for a 7-day sparkline (last 7 days). Values normalized 0–30.
        var dailyMileBars: [Double]
        var activeDayIndex: Int

        /// Placeholder-friendly fallback used before any trips exist.
        static let empty = WeeklySummary(
            miles: 0,
            vsLastWeekPct: 0,
            dailyMileBars: [0, 0, 0, 0, 0, 0, 0],
            activeDayIndex: 6
        )
    }

    struct QuickStats: Equatable {
        var trips: Int
        var clipsLocked: Int
        var topSpeedMPH: Int
        var incidents: Int

        static let empty = QuickStats(trips: 0, clipsLocked: 0, topSpeedMPH: 0, incidents: 0)
    }

    struct LastTrip: Equatable {
        var minutesAgo: Int
        var endLocation: String

        static let placeholder = LastTrip(minutesAgo: 16, endLocation: "last drop-off")
    }

    var weeklySummary: WeeklySummary = .empty
    var quickStats: QuickStats = .empty
    var lastTrip: LastTrip?
    var todayDate: String = ""

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    init() {
        todayDate = formatter.string(from: Date()).uppercased()
    }

    /// Pulls aggregate stats from SwiftData. Keeps the read cheap by using a
    /// FetchDescriptor bounded to the last 8 days.
    func refresh(context: ModelContext?) {
        guard let context else { return }

        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date()

        var descriptor = FetchDescriptor<RecordingSession>(
            predicate: #Predicate { $0.startDate >= weekAgo },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        guard let sessions = try? context.fetch(descriptor) else { return }

        // Weekly miles + sparkline.
        var dailyMiles = [Double](repeating: 0, count: 7)
        let today = calendar.startOfDay(for: Date())

        var weeklyMiles: Double = 0
        var weeklyTrips = 0
        var peakMPH: Double = 0
        var lockedClips = 0
        var incidents = 0

        for session in sessions {
            let dayStart = calendar.startOfDay(for: session.startDate)
            if let offset = calendar.dateComponents([.day], from: dayStart, to: today).day {
                let idx = 6 - offset
                if idx >= 0 && idx < 7 {
                    let miles = session.totalDistanceMeters / 1609.344
                    dailyMiles[idx] += miles
                    weeklyMiles += miles
                    weeklyTrips += 1
                    peakMPH = max(peakMPH, session.peakSpeedMPH)
                    lockedClips += session.lockedClipCount
                    incidents += session.incidentCount
                }
            }
        }

        let maxMiles = max(dailyMiles.max() ?? 1, 1)
        let bars = dailyMiles.map { ($0 / maxMiles) * 30 }

        weeklySummary = WeeklySummary(
            miles: weeklyMiles,
            vsLastWeekPct: 0,
            dailyMileBars: bars,
            activeDayIndex: 6
        )

        quickStats = QuickStats(
            trips: weeklyTrips,
            clipsLocked: lockedClips,
            topSpeedMPH: Int(peakMPH.rounded()),
            incidents: incidents
        )

        if let latest = sessions.first, let end = latest.endDate {
            let minutes = max(0, Int(Date().timeIntervalSince(end) / 60))
            lastTrip = LastTrip(
                minutesAgo: minutes,
                endLocation: latest.endLocationLabel ?? "last drop-off"
            )
        }
    }
}
