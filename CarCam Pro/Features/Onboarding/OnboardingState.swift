import Foundation
import SwiftUI

/// Single source of truth for the onboarding step + completion flag.
/// Completion is persisted so the user only sees onboarding once.
///
/// The step list moved to a 6-step flow to cover sign-in + paywall:
///   1. welcome
///   2. signIn
///   3. permissions
///   4. calibration
///   5. paywall
///   6. ready
///
/// `signIn` and `paywall` are skippable. Skipped users run on FREE tier
/// against the local-only feature set; they can sign in / upgrade later
/// from Settings.
@Observable
@MainActor
final class OnboardingState {
    enum Step: Int, CaseIterable {
        case welcome = 1
        case signIn = 2
        case permissions = 3
        case calibration = 4
        case paywall = 5
        case ready = 6

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
