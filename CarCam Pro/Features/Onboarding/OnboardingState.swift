import Foundation
import SwiftUI

/// Single source of truth for the onboarding step + completion flag.
/// Completion is persisted so the user only sees onboarding once.
@Observable
@MainActor
final class OnboardingState {
    enum Step: Int, CaseIterable {
        case welcome = 1
        case permissions = 2
        case calibration = 3
        case ready = 4

        var total: Int { Step.allCases.count }
    }

    private let completionKey = "onboarding.completed"

    var step: Step = .welcome
    var pitchDegrees: Double = 0
    var rollDegrees: Double = 0

    var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completionKey) }
        set { UserDefaults.standard.set(newValue, forKey: completionKey) }
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            complete()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = next
        }
    }

    func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = prev
        }
    }

    func complete() {
        isCompleted = true
    }

    /// For developer menus / reset flow — resets onboarding so it re-plays
    /// on next launch.
    func reset() {
        isCompleted = false
        step = .welcome
    }
}
