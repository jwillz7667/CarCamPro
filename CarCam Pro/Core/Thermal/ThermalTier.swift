import Foundation

/// Four thermal tiers — map 1:1 from `ProcessInfo.ThermalState` but include
/// the specific quality-policy payload the recording pipeline consumes.
///
/// The tiers implement the 4-tier thermal management spec from CLAUDE.md:
/// aggressive downshifting prevents the #1 competing-app complaint (thermal
/// shutdown within 30-60 min of continuous recording).
enum ThermalTier: Int, CaseIterable, Sendable {
    case nominal = 0
    case fair    = 1
    case serious = 2
    case critical = 3

    init(processInfoState: ProcessInfo.ThermalState) {
        switch processInfoState {
        case .nominal:  self = .nominal
        case .fair:     self = .fair
        case .serious:  self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    /// Human-readable tier label (rendered verbatim in the UI).
    var label: String {
        switch self {
        case .nominal:  return "NOMINAL"
        case .fair:     return "FAIR"
        case .serious:  return "SERIOUS"
        case .critical: return "CRITICAL"
        }
    }

    /// Framerate ceiling for this tier.
    var maxFrameRate: Int {
        switch self {
        case .nominal:  return 60
        case .fair:     return 24
        case .serious:  return 24
        case .critical: return 15
        }
    }

    /// Bitrate in Mbps — multiplicatively applied against user-configured value.
    var bitrateMultiplier: Double {
        switch self {
        case .nominal:  return 1.0
        case .fair:     return 0.80
        case .serious:  return 0.50
        case .critical: return 0.30
        }
    }

    /// Hard ceiling resolution — forces 720p once we hit `.serious`.
    var forcedResolutionCeiling: VideoResolution? {
        switch self {
        case .nominal, .fair: return nil
        case .serious, .critical: return .hd720
        }
    }

    /// Suggested screen brightness (0 = off, 1 = user-configured).
    var brightnessFactor: Double {
        switch self {
        case .nominal:  return 1.0
        case .fair:     return 0.6
        case .serious:  return 0.2
        case .critical: return 0.0
        }
    }

    /// Should incident detection run at reduced sample rate (or pause)?
    var incidentSampleRateHz: Double? {
        switch self {
        case .nominal:  return 60
        case .fair:     return 60
        case .serious:  return 10
        case .critical: return nil
        }
    }
}
