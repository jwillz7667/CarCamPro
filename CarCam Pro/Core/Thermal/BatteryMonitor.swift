import Foundation
import UIKit
import OSLog

/// Battery pressure mirrored onto the same 4-tier ladder as `ThermalTier`.
/// The idea: thermal and battery both constrain how aggressively we can
/// record; mapping them onto a shared ladder lets a single fused
/// `effectiveTier` drive every downstream throttling decision.
enum BatteryTier: Int, CaseIterable, Sendable {
    case nominal = 0   // charging OR battery > 50 %
    case fair    = 1   // 20 %…50 %, not charging
    case serious = 2   // 10 %…20 %, not charging
    case critical = 3  // < 10 % OR Low-Power Mode enabled
}

/// Observes `UIDevice.batteryLevel` + `batteryState` and publishes a
/// `BatteryTier` on the main actor.
///
/// Three reasons battery matters independently of thermal:
///   1. A cool device on 8 % battery should still throttle — users don't
///      expect a dashcam to drain their phone in 15 minutes on the way
///      to a meeting.
///   2. Low-Power Mode (`ProcessInfo.isLowPowerModeEnabled`) disables
///      background refresh and clamps the CPU — ignoring it mid-session
///      produces frame drops we'd otherwise blame on thermal.
///   3. While charging (CarPlay, 12 V USB adapter, wireless puck) we can
///      safely record at full quality regardless of the battery level.
@Observable
@MainActor
final class BatteryMonitor {
    private(set) var level: Float = 1.0             // 0…1
    private(set) var state: UIDevice.BatteryState = .unknown
    private(set) var isLowPowerMode: Bool = false
    private(set) var currentTier: BatteryTier = .nominal

    private var subscribers: [@MainActor (BatteryTier) -> Void] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        // Enabling battery monitoring is cheap — it just starts UIKit
        // delivering the two notifications we care about.
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshFromDevice()
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFromDevice() }
        })

        observers.append(center.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFromDevice() }
        })

        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFromDevice() }
        })

        AppLogger.thermal.info("Battery monitor started (initial tier: \(self.currentTier.label))")
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Subscribe to tier transitions. Callback fires on the main actor.
    func onTierChange(_ handler: @escaping @MainActor (BatteryTier) -> Void) {
        subscribers.append(handler)
    }

    // MARK: - Internals

    private func refreshFromDevice() {
        let device = UIDevice.current
        let previousTier = currentTier
        level = device.batteryLevel                     // −1 in simulator
        state = device.batteryState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let newTier = Self.tier(level: level, state: state, lowPowerMode: isLowPowerMode)
        currentTier = newTier

        if newTier != previousTier {
            AppLogger.thermal.info(
                "Battery tier: \(previousTier.label) → \(newTier.label) (level=\(self.level), lpm=\(self.isLowPowerMode))"
            )
            for handler in subscribers { handler(newTier) }
        }
    }

    /// Pure mapping — exposed for unit testing without a live UIDevice.
    static func tier(
        level: Float,
        state: UIDevice.BatteryState,
        lowPowerMode: Bool
    ) -> BatteryTier {
        // Charging wins unconditionally — recording while plugged in is
        // the expected "mounted on the windshield" use case.
        if state == .charging || state == .full {
            return .nominal
        }
        if lowPowerMode {
            return .critical
        }
        // `UIDevice.batteryLevel == -1` means "unknown" (simulator, or an
        // edge-case on iPads without a battery). Treat as nominal.
        guard level >= 0 else { return .nominal }

        switch level {
        case ..<0.10: return .critical
        case 0.10..<0.20: return .serious
        case 0.20..<0.50: return .fair
        default: return .nominal
        }
    }
}

extension BatteryTier {
    var label: String {
        switch self {
        case .nominal:  return "NOMINAL"
        case .fair:     return "FAIR"
        case .serious:  return "SERIOUS"
        case .critical: return "CRITICAL"
        }
    }
}
