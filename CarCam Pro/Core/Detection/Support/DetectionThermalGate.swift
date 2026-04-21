import Foundation

/// Rate-limits the detection pipeline based on device thermal state.
///
/// Distinct from the app-wide `ThermalMonitor` which drives the recording
/// pipeline's quality policy — this gate just decides whether a given frame
/// should be handed to the ML models. Skipping frames is free; dropping
/// detections risks missing a fast-moving cruiser.
final class DetectionThermalGate: @unchecked Sendable {
    static let shared = DetectionThermalGate()

    private var frameCounter: Int = 0
    private let lock = NSLock()

    /// Target inference frequency varies with thermal state.
    /// Returns "process every Nth frame" where higher = less frequent.
    var framesPerInference: Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:    return 2    // ~30 fps → 15 Hz inference
        case .fair:       return 3    // ~10 Hz
        case .serious:    return 6    // ~5 Hz
        case .critical:   return 15   // ~2 Hz
        @unknown default: return 3
        }
    }

    func shouldProcessThisFrame() -> Bool {
        lock.lock(); defer { lock.unlock() }
        frameCounter += 1
        return frameCounter % framesPerInference == 0
    }
}
