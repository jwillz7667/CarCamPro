import Foundation

/// Combines per-signal scores into a unified threat assessment per vehicle,
/// with temporal smoothing + hysteresis to prevent single-frame false alerts.
final class DetectionFusion: @unchecked Sendable {
    // Threshold ladders for sustained detection.
    private let alertThreshold: Float = 0.55
    private let confirmedThreshold: Float = 0.75
    private let minSustainedFramesForAlert = 4   // ~0.3 s at 15 fps

    /// Final assessment for a track given the latest per-signal scores.
    /// Mutates the track's rolling buffers + sustained-frame counter.
    func assess(
        track: VehicleTrack,
        emergency: EmergencyLightSignal,
        roof: RoofSignal,
        fleet: FleetFeatureSignal
    ) -> VehicleThreatAssessment {
        // Record into the track's rolling buffers for smoothing.
        track.recordEmergencyScore(emergency.score)
        track.recordLightBarScore(roof.lightBarScore)
        track.recordRoofRailsScore(roof.roofRailsScore)
        let fleetCombined = (
            fleet.pushBarScore + fleet.spotlightScore +
            fleet.blackoutWheelsScore + fleet.antennaScore
        ) / 4.0
        track.recordFleetFeatureScore(fleetCombined)

        let smEmerg = track.smoothedEmergencyScore()
        let smLightBar = track.smoothedLightBarScore()
        let smRoofRails = track.smoothedRoofRailsScore()
        let smFleet = track.smoothedFleetFeatureScore()

        var reasoning: [String] = []
        var score: Float = 0

        // Signal 1 — active emergency lights (dominant).
        if smEmerg > 0.4 {
            score = max(score, 0.80 + 0.20 * smEmerg)
            reasoning.append("active emergency lights (\(Int(smEmerg * 100))%)")
            if emergency.bicolor {
                reasoning.append("red+blue @ \(String(format: "%.1f", emergency.frequencyHz)) Hz")
            }
        }

        // Signal 2 — roof light bar (marked cruiser).
        if smLightBar > 0.55 {
            let contribution: Float = 0.55 + 0.35 * smLightBar
            score = max(score, contribution)
            reasoning.append("roof light bar (\(Int(smLightBar * 100))%)")
        }

        // Signal 3 — unmarked fleet pattern (only on fleet-capable models).
        let fleetCapable = track.lastDetection.fleetCapableModel != .unknown
        if fleetCapable {
            let missingRails = max(0, 1.0 - smRoofRails)
            let railsInformative = (smRoofRails < 0.35 || smRoofRails > 0.65)

            var fleetScore: Float = 0
            if railsInformative {
                fleetScore += 0.45 * missingRails
            }
            fleetScore += 0.35 * smFleet
            fleetScore += 0.20 * track.lastDetection.confidence

            if fleetScore > 0.45 {
                score = max(score, min(fleetScore, 0.85))
                reasoning.append("fleet pattern on \(track.lastDetection.fleetCapableModel.rawValue)")
                if railsInformative && missingRails > 0.6 {
                    reasoning.append("no civilian roof rails")
                }
                if smFleet > 0.4 {
                    reasoning.append("fleet-spec features (bars / spots / wheels / antennas)")
                }
            }
        }

        // Hysteresis — require sustained frames before escalating.
        track.incrementSustainedIfThreshold(alertThreshold, currentFused: score)

        let level: ThreatLevel
        switch score {
        case ..<0.25:
            level = .none
        case 0.25..<alertThreshold:
            level = .low
        case alertThreshold..<confirmedThreshold:
            level = track.sustainedFrames >= minSustainedFramesForAlert ? .likely : .possible
        default:
            level = track.sustainedFrames >= minSustainedFramesForAlert ? .confirmed : .likely
        }

        return VehicleThreatAssessment(
            id: track.id,
            detection: track.lastDetection,
            emergencyLights: emergency,
            roof: roof,
            fleetFeatures: fleet,
            fusedScore: score,
            threatLevel: level,
            reasoning: reasoning,
            sustainedFrames: track.sustainedFrames
        )
    }
}
