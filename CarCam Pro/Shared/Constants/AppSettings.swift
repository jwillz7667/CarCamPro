import Foundation
import Observation

/// Single source of truth for all user-facing preferences. Backed by
/// `UserDefaults` so values survive launches; `@Observable` so SwiftUI views
/// bound to individual properties redraw automatically on change.
///
/// Every setting here maps 1:1 to a control on the Settings screen and has a
/// matching side-effect wired in `SettingsCoordinator`.
@Observable
final class AppSettings {
    @ObservationIgnored
    static let shared = AppSettings()

    @ObservationIgnored
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Capture

    var resolution: VideoResolution {
        get { VideoResolution(rawValue: defaults.string(forKey: Keys.resolution) ?? "") ?? .hd1080 }
        set { defaults.set(newValue.rawValue, forKey: Keys.resolution) }
    }

    var frameRate: Int {
        get {
            let value = defaults.integer(forKey: Keys.frameRate)
            return value > 0 ? value : 30
        }
        set { defaults.set(newValue, forKey: Keys.frameRate) }
    }

    var codec: VideoCodec {
        get { VideoCodec(rawValue: defaults.string(forKey: Keys.codec) ?? "") ?? .hevc }
        set { defaults.set(newValue.rawValue, forKey: Keys.codec) }
    }

    /// User-configured bitrate multiplier applied on top of the resolution's
    /// default bitrate (0.5 … 2.0). Default = 1.0.
    var bitrateMultiplier: Double {
        get {
            let value = defaults.double(forKey: Keys.bitrateMultiplier)
            return value > 0 ? value : 1.0
        }
        set { defaults.set(newValue.clamped(to: 0.5...2.0), forKey: Keys.bitrateMultiplier) }
    }

    var audioEnabled: Bool {
        get { defaults.object(forKey: Keys.audioEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.audioEnabled) }
    }

    var selectedCamera: CameraPosition {
        get { CameraPosition(rawValue: defaults.string(forKey: Keys.selectedCamera) ?? "") ?? .backWide }
        set { defaults.set(newValue.rawValue, forKey: Keys.selectedCamera) }
    }

    var segmentDuration: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.segmentDuration)
            return value > 0 ? value : AppConstants.defaultSegmentDuration
        }
        set { defaults.set(newValue, forKey: Keys.segmentDuration) }
    }

    // MARK: - Storage

    var storageCap: Int64 {
        get { defaults.object(forKey: Keys.storageCap) as? Int64 ?? AppConstants.defaultStorageCap }
        set { defaults.set(newValue, forKey: Keys.storageCap) }
    }

    var autoExportToPhotos: Bool {
        get { defaults.object(forKey: Keys.autoExportToPhotos) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.autoExportToPhotos) }
    }

    var iCloudBackupEnabled: Bool {
        get { defaults.bool(forKey: Keys.iCloudBackupEnabled) }
        set { defaults.set(newValue, forKey: Keys.iCloudBackupEnabled) }
    }

    // MARK: - Incident detection

    var incidentDetectionEnabled: Bool {
        get { defaults.object(forKey: Keys.incidentDetectionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.incidentDetectionEnabled) }
    }

    var incidentSensitivity: IncidentSensitivity {
        get { IncidentSensitivity(rawValue: defaults.string(forKey: Keys.incidentSensitivity) ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Keys.incidentSensitivity) }
    }

    var parkingSentryEnabled: Bool {
        get { defaults.bool(forKey: Keys.parkingSentryEnabled) }
        set { defaults.set(newValue, forKey: Keys.parkingSentryEnabled) }
    }

    var hardBrakeDetectionEnabled: Bool {
        get { defaults.object(forKey: Keys.hardBrakeDetectionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.hardBrakeDetectionEnabled) }
    }

    // MARK: - Overlay (baked into exported MP4)

    var showSpeedOverlay: Bool {
        get { defaults.object(forKey: Keys.showSpeedOverlay) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showSpeedOverlay) }
    }

    var showGPSOverlay: Bool {
        get { defaults.object(forKey: Keys.showGPSOverlay) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showGPSOverlay) }
    }

    var showGForceOverlay: Bool {
        get { defaults.bool(forKey: Keys.showGForceOverlay) }
        set { defaults.set(newValue, forKey: Keys.showGForceOverlay) }
    }

    var watermarkEnabled: Bool {
        get { defaults.bool(forKey: Keys.watermarkEnabled) }
        set { defaults.set(newValue, forKey: Keys.watermarkEnabled) }
    }

    var watermarkText: String {
        get { defaults.string(forKey: Keys.watermarkText) ?? "CarCam Pro" }
        set { defaults.set(newValue, forKey: Keys.watermarkText) }
    }

    // MARK: - Behavior / display

    var autoStartOnLaunch: Bool {
        get { defaults.bool(forKey: Keys.autoStartOnLaunch) }
        set { defaults.set(newValue, forKey: Keys.autoStartOnLaunch) }
    }

    var dimDisplayWhileRecording: Bool {
        get { defaults.object(forKey: Keys.dimDisplayWhileRecording) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.dimDisplayWhileRecording) }
    }

    var allowThermalThrottling: Bool {
        get { defaults.object(forKey: Keys.allowThermalThrottling) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.allowThermalThrottling) }
    }

    var hapticsEnabled: Bool {
        get { defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.hapticsEnabled) }
    }

    // MARK: - Detection

    /// Enables the on-device police / emergency-vehicle detection subsystem.
    /// When false, frames skip the ML pipeline entirely.
    var policeDetectionEnabled: Bool {
        get { defaults.bool(forKey: Keys.policeDetectionEnabled) }
        set { defaults.set(newValue, forKey: Keys.policeDetectionEnabled) }
    }

    /// Whether to play an audible chime on confirmed detections.
    var detectionAudioEnabled: Bool {
        get { defaults.object(forKey: Keys.detectionAudioEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.detectionAudioEnabled) }
    }

    // MARK: - Keys (private)

    private enum Keys {
        static let resolution = "resolution"
        static let frameRate = "frameRate"
        static let codec = "codec"
        static let bitrateMultiplier = "bitrateMultiplier"
        static let audioEnabled = "audioEnabled"
        static let selectedCamera = "selectedCamera"
        static let segmentDuration = "segmentDuration"
        static let storageCap = "storageCap"
        static let autoExportToPhotos = "autoExportToPhotos"
        static let iCloudBackupEnabled = "iCloudBackupEnabled"
        static let incidentDetectionEnabled = "incidentDetectionEnabled"
        static let incidentSensitivity = "incidentSensitivity"
        static let parkingSentryEnabled = "parkingSentryEnabled"
        static let hardBrakeDetectionEnabled = "hardBrakeDetectionEnabled"
        static let showSpeedOverlay = "showSpeedOverlay"
        static let showGPSOverlay = "showGPSOverlay"
        static let showGForceOverlay = "showGForceOverlay"
        static let watermarkEnabled = "watermarkEnabled"
        static let watermarkText = "watermarkText"
        static let autoStartOnLaunch = "autoStartOnLaunch"
        static let dimDisplayWhileRecording = "dimDisplayWhileRecording"
        static let allowThermalThrottling = "allowThermalThrottling"
        static let hapticsEnabled = "hapticsEnabled"
        static let policeDetectionEnabled = "policeDetectionEnabled"
        static let detectionAudioEnabled = "detectionAudioEnabled"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
