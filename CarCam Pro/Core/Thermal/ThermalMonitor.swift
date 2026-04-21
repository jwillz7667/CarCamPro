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

    /// Pure thermal signal from `ProcessInfo.thermalState`. Use
    /// `effectiveTier` to drive throttling decisions — it folds in battery
    /// pressure so low-battery + cool-device ships policies, not raw.
    private(set) var currentTier: ThermalTier = .nominal
    private(set) var rawState: ProcessInfo.ThermalState = .nominal
    private(set) var lastTransition: Date = Date()

    /// Fused tier: `max(thermalTier, batteryTier)` when a `BatteryMonitor`
    /// has been attached, else equal to `currentTier`. The recording
    /// pipeline binds to this so a single notification fires when either
    /// constraint tightens.
    private(set) var effectiveTier: ThermalTier = .nominal

    private var observation: NSObjectProtocol?
    private var pendingRecoveryTask: Task<Void, Never>?
    private var tierSubscribers: [@MainActor (ThermalTier) -> Void] = []
    private weak var batteryMonitor: BatteryMonitor?

    init() {
        self.rawState = ProcessInfo.processInfo.thermalState
        self.currentTier = ThermalTier(processInfoState: rawState)
        self.effectiveTier = self.currentTier
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

    /// Subscribe to effective-tier transitions. Callback fires on the main
    /// actor. Subscribers observe the *fused* tier (thermal OR battery),
    /// which is what they typically want for throttling decisions.
    func onTierChange(_ handler: @escaping @MainActor (ThermalTier) -> Void) {
        tierSubscribers.append(handler)
    }

    /// Bind a battery monitor — its tier is folded into `effectiveTier`
    /// via `max`. Safe to call multiple times; only the most recent
    /// monitor is tracked.
    func attach(batteryMonitor: BatteryMonitor) {
        self.batteryMonitor = batteryMonitor
        recomputeEffective(batteryTier: batteryMonitor.currentTier)
        batteryMonitor.onTierChange { [weak self] newBatteryTier in
            self?.recomputeEffective(batteryTier: newBatteryTier)
        }
    }

    /// Recompute `effectiveTier` from the pure thermal tier + an explicit
    /// battery tier. Exposed internal-only so the battery-change callback
    /// and thermal-change paths share one sink.
    private func recomputeEffective(batteryTier: BatteryTier) {
        let rank = max(currentTier.rawValue, batteryTier.rawValue)
        let fused = ThermalTier(rawValue: rank) ?? .nominal
        let previous = effectiveTier
        effectiveTier = fused
        if fused != previous {
            AppLogger.thermal.info(
                "Effective tier: \(previous.label) → \(fused.label) (thermal=\(self.currentTier.label), battery=\(batteryTier.label))"
            )
            for handler in tierSubscribers { handler(fused) }
        }
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
        // Recompute the fused tier + notify via that path — subscribers
        // always hear about thermal+battery as a single signal.
        recomputeEffective(batteryTier: batteryMonitor?.currentTier ?? .nominal)
    }
}
