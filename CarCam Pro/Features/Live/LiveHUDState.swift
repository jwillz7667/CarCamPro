import Foundation
import SwiftUI

/// Aggregates everything the live HUD renders — wired by `LiveCamView` so the
/// view body is pure rendering. State mutations happen on the main actor.
@Observable
@MainActor
final class LiveHUDState {
    var speedMPH: Double = 0
    var speedLimitMPH: Int = 65
    var heading: Double = 0
    var compass: String = "—"
    var altitudeFeet: Int = 0
    var coordinateLabel: String = "--.---- ° ·  --.---- °"
    var roadLabel: String = ""

    var totalG: Double = 0
    var peakG: Double = 0
    var gAxisX: Double = 0
    var gAxisY: Double = 0

    var currentBufferSeconds: TimeInterval = 0
    var loopBufferSeconds: TimeInterval = 90 * 60
    var lockedMarkers: [Double] = []
}
