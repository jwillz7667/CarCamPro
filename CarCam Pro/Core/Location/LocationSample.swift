import Foundation
import CoreLocation

/// Snapshot of vehicle location — attached to `VideoClip` and rendered in HUDs.
struct LocationSample: Sendable, Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    /// Speed in meters/second. Negative = unknown.
    let speedMPS: Double
    /// Heading in degrees (0 = north). Negative = unknown.
    let courseDegrees: Double
    let horizontalAccuracy: Double

    /// Speed in miles per hour, or nil if unknown.
    var speedMPH: Double? {
        guard speedMPS >= 0 else { return nil }
        return speedMPS * 2.23694
    }

    /// Compass cardinal abbreviation for the current course (e.g. "NE").
    var compass: String? {
        guard courseDegrees >= 0 else { return nil }
        let sectors = ["N","NE","E","SE","S","SW","W","NW"]
        let idx = Int((courseDegrees / 45.0).rounded()) % 8
        return sectors[idx]
    }

    nonisolated init(from loc: CLLocation) {
        self.timestamp = loc.timestamp
        self.latitude = loc.coordinate.latitude
        self.longitude = loc.coordinate.longitude
        self.altitudeMeters = loc.altitude
        self.speedMPS = loc.speed
        self.courseDegrees = loc.course
        self.horizontalAccuracy = loc.horizontalAccuracy
    }
}
