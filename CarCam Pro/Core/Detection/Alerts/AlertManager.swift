import Foundation
import AVFoundation
import UIKit
import Observation
import OSLog

/// Debounces and publishes detection alerts for the UI layer.
///
/// `@Observable` + `@MainActor` so SwiftUI views can consume `activeThreats`
/// directly. `publish(assessments:)` is called from a background detection
/// pipeline and hops to the main actor internally.
@Observable
@MainActor
final class AlertManager {
    static let shared = AlertManager()

    private(set) var activeThreats: [VehicleThreatAssessment] = []

    private let hapticGenerator = UINotificationFeedbackGenerator()
    private var lastAlertAt: [UUID: TimeInterval] = [:]
    private let minAlertIntervalSeconds: TimeInterval = 4.0

    private var audioPlayer: AVAudioPlayer?

    private init() {
        hapticGenerator.prepare()
    }

    /// Receive a fresh batch of per-vehicle assessments. Updates the
    /// published `activeThreats`, fires debounced alerts, and GCs stale
    /// alert timestamps.
    nonisolated func publish(assessments: [VehicleThreatAssessment]) {
        Task { @MainActor in
            self.applyAssessments(assessments)
        }
    }

    private func applyAssessments(_ assessments: [VehicleThreatAssessment]) {
        activeThreats = assessments.filter { $0.threatLevel >= .possible }
        let alertable = assessments.filter { $0.threatLevel >= .likely }

        let now = Date().timeIntervalSince1970
        for a in alertable {
            let last = lastAlertAt[a.id] ?? 0
            guard now - last >= minAlertIntervalSeconds else { continue }
            lastAlertAt[a.id] = now
            fireAlert(for: a)
        }

        // Garbage-collect debounce entries older than 60 s.
        lastAlertAt = lastAlertAt.filter { now - $0.value < 60 }
    }

    private func fireAlert(for a: VehicleThreatAssessment) {
        hapticGenerator.notificationOccurred(
            a.threatLevel == .confirmed ? .warning : .success
        )
        playChime(urgent: a.threatLevel == .confirmed)
        AppLogger.detection.notice(
            "Alert \(String(describing: a.threatLevel)) score=\(a.fusedScore) reasons=\(a.reasoning.joined(separator: ", "))"
        )
    }

    private func playChime(urgent: Bool) {
        let name = urgent ? "chime_urgent" : "chime_subtle"
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 0.9
            audioPlayer?.play()
        } catch {
            AppLogger.detection.error("AlertManager.playChime: \(error.localizedDescription)")
        }
    }

    /// Clear all active threats — called when detection is disabled or the
    /// user leaves the live camera view.
    func reset() {
        activeThreats = []
        lastAlertAt.removeAll()
    }
}
