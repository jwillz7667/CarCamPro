import Foundation
import SwiftData

@Model
final class RecordingSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var totalDuration: TimeInterval
    var totalSegments: Int
    var wasInterrupted: Bool

    /// Cumulative drive distance in meters (filled in from location samples).
    var totalDistanceMeters: Double = 0
    /// Peak recorded speed in miles per hour.
    var peakSpeedMPH: Double = 0
    /// Count of clips marked locked/protected in this session.
    var lockedClipCount: Int = 0
    /// Count of detected impact incidents in this session.
    var incidentCount: Int = 0
    /// Human-readable label for the session's endpoint (e.g. "Home → Office").
    var routeLabel: String?
    /// Last-known resolved location string at session end (e.g. "1.4 Maple St").
    var endLocationLabel: String?

    @Relationship(deleteRule: .cascade, inverse: \VideoClip.session)
    var clips: [VideoClip]

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        totalDuration: TimeInterval = 0,
        totalSegments: Int = 0,
        wasInterrupted: Bool = false
    ) {
        self.id = id
        self.startDate = startDate
        self.totalDuration = totalDuration
        self.totalSegments = totalSegments
        self.wasInterrupted = wasInterrupted
        self.clips = []
    }

    var shortID: String {
        String(id.uuidString.prefix(6)).lowercased()
    }
}
