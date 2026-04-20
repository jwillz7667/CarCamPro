import Foundation
import OSLog

/// Observes `ProcessInfo.thermalState` and publishes a computed `ThermalTier`.
///
/// A 60-second "recovery delay" prevents oscillation between tiers when the
/// SoC's temperature fluctuates right at a threshold. Downshifting is applied
/// immediately; upshifting (moving back to a cooler tier) waits the delay.
///
/// Observer pattern: subscribers call `start()` to begin receiving tier
/// transitions on the main actor. A single instance is shared via the
/// DependencyContainer.
@Observable
@MainActor
final class ThermalMonitor {
    /// Minimum delay before stepping back down to a cooler tier.
    static let recoveryDelay: TimeInterval = 60

    private(set) var currentTier: ThermalTier = .nominal
    private(set) var rawState: ProcessInfo.ThermalState = .nominal
    private(set) var lastTransition: Date = Date()

    private var observation: NSObjectProtocol?
    private var pendingRecoveryTask: Task<Void, Never>?
    private var tierSubscribers: [@MainActor (ThermalTier) -> Void] = []

    init() {
        self.rawState = ProcessInfo.processInfo.thermalState
        self.currentTier = ThermalTier(processInfoState: rawState)
    }

    /// Begin observing the system thermal state. Safe to call repeatedly.
    func start() {
        guard observation == nil else { return }
        observation = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleThermalChange()
            }
        }
        AppLogger.thermal.info("Thermal monitor started (initial tier: \(self.currentTier.label))")
    }

    func stop() {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
        observation = nil
        pendingRecoveryTask?.cancel()
        pendingRecoveryTask = nil
    }

    /// Subscribe to tier transitions. Callback fires on the main actor.
    func onTierChange(_ handler: @escaping @MainActor (ThermalTier) -> Void) {
        tierSubscribers.append(handler)
    }

    // MARK: - Private

    private func handleThermalChange() {
        let newRaw = ProcessInfo.processInfo.thermalState
        rawState = newRaw
        let proposed = ThermalTier(processInfoState: newRaw)

        if proposed.rawValue > currentTier.rawValue {
            // Downshift immediately (thermal pressure increasing).
            pendingRecoveryTask?.cancel()
            pendingRecoveryTask = nil
            apply(proposed)
        } else if proposed.rawValue < currentTier.rawValue {
            // Upshift (cooler tier) — wait out the recovery window.
            scheduleRecovery(to: proposed)
        }
    }

    private func scheduleRecovery(to target: ThermalTier) {
        pendingRecoveryTask?.cancel()
        pendingRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.recoveryDelay))
            guard let self, !Task.isCancelled else { return }
            // Only apply if we're still trending cooler.
            let latest = ThermalTier(processInfoState: ProcessInfo.processInfo.thermalState)
            if latest.rawValue <= target.rawValue {
                self.apply(target)
            }
        }
    }

    private func apply(_ tier: ThermalTier) {
        let previous = currentTier
        currentTier = tier
        lastTransition = Date()
        AppLogger.thermal.info("Thermal tier: \(previous.label) → \(tier.label)")
        for handler in tierSubscribers { handler(tier) }
    }
}
