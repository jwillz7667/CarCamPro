import Foundation
import UIKit
import Testing
@testable import CarCam_Pro

/// Unit coverage for the battery-aware thermal fusion that drives every
/// recording-quality throttling decision in the app.
///
/// Covers:
///   • `BatteryMonitor.tier(level:state:lowPowerMode:)` pure mapping —
///     charging beats everything, LPM forces critical, band boundaries.
///   • `BatteryTier` rawValues match `ThermalTier` rawValues so
///     `ThermalMonitor.recomputeEffective` can fuse with a plain `max`.
///   • Attaching a `BatteryMonitor` doesn't crash and leaves
///     `effectiveTier` sane (≥ thermalTier).
@Suite("Thermal × Battery — fusion + mapping", .serialized)
struct ThermalBatteryTests {

    // MARK: - BatteryMonitor.tier(...)

    @Test("Charging returns nominal regardless of level")
    func chargingBeatsEverything() {
        #expect(BatteryMonitor.tier(level: 0.01, state: .charging, lowPowerMode: false) == .nominal)
        #expect(BatteryMonitor.tier(level: 0.05, state: .full,     lowPowerMode: true)  == .nominal)
        #expect(BatteryMonitor.tier(level: 0.99, state: .charging, lowPowerMode: false) == .nominal)
    }

    @Test("Low-Power Mode forces critical when unplugged")
    func lowPowerModeIsCritical() {
        #expect(BatteryMonitor.tier(level: 0.80, state: .unplugged, lowPowerMode: true) == .critical)
    }

    @Test("Unknown level (-1, simulator) treated as nominal")
    func unknownLevelIsNominal() {
        #expect(BatteryMonitor.tier(level: -1.0, state: .unknown, lowPowerMode: false) == .nominal)
    }

    @Test("Battery level band boundaries")
    func bandBoundaries() {
        #expect(BatteryMonitor.tier(level: 0.05, state: .unplugged, lowPowerMode: false) == .critical)
        #expect(BatteryMonitor.tier(level: 0.09, state: .unplugged, lowPowerMode: false) == .critical)
        #expect(BatteryMonitor.tier(level: 0.10, state: .unplugged, lowPowerMode: false) == .serious)
        #expect(BatteryMonitor.tier(level: 0.19, state: .unplugged, lowPowerMode: false) == .serious)
        #expect(BatteryMonitor.tier(level: 0.20, state: .unplugged, lowPowerMode: false) == .fair)
        #expect(BatteryMonitor.tier(level: 0.49, state: .unplugged, lowPowerMode: false) == .fair)
        #expect(BatteryMonitor.tier(level: 0.50, state: .unplugged, lowPowerMode: false) == .nominal)
        #expect(BatteryMonitor.tier(level: 0.99, state: .unplugged, lowPowerMode: false) == .nominal)
    }

    // MARK: - Rank alignment

    @Test("BatteryTier rawValue mirrors ThermalTier rawValue — fusion by max works")
    func rawValuesMatch() {
        #expect(BatteryTier.nominal.rawValue  == ThermalTier.nominal.rawValue)
        #expect(BatteryTier.fair.rawValue     == ThermalTier.fair.rawValue)
        #expect(BatteryTier.serious.rawValue  == ThermalTier.serious.rawValue)
        #expect(BatteryTier.critical.rawValue == ThermalTier.critical.rawValue)
    }

    // MARK: - Smoke test: ThermalMonitor.attach()

    @Test("Attaching a BatteryMonitor leaves effectiveTier ≥ currentTier")
    @MainActor
    func attachNeverDemotesThermal() {
        let thermal = ThermalMonitor()
        let battery = BatteryMonitor()
        thermal.attach(batteryMonitor: battery)
        #expect(thermal.effectiveTier.rawValue >= thermal.currentTier.rawValue)
    }
}
