import Foundation
import Observation

/// Single source of truth for all user-facing preferences.
///
/// Reads come from the local `UserDefaults` (hot path — no I/O, no
/// notifications). Writes fan out through `CloudSettingsStore` to both
/// `UserDefaults` *and* `NSUbiquitousKeyValueStore`, so every preference
/// automatically roams to the customer's other iCloud-bound devices.
///
/// `@Observable` so SwiftUI views bound to individual properties redraw
/// automatically on change — both when the user flips a toggle locally
/// AND when an external iCloud push lands (see
/// `DependencyContainer.configure` where the bootstrap observer calls
/// `AppSettings.notifyExternalChange`).
@Observable
final class AppSettings {
    @ObservationIgnored
    static let shared = AppSettings()

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let cloud: CloudSettingsStore

    private init(
        defaults: UserDefaults = .standard,
        cloud: CloudSettingsStore = .shared
    ) {
        self.defaults = defaults
        self.cloud = cloud
    }

    // MARK: - Capture

    var resolution: VideoResolution {
        get { VideoResolution(rawValue: defaults.string(forKey: Keys.resolution) ?? "") ?? .hd1080 }
        set { cloud.writeThrough(newValue.rawValue, forKey: Keys.resolution) }
    }

    var frameRate: Int {
        get {
            let value = defaults.integer(forKey: Keys.frameRate)
            return value > 0 ? value : 30
        }
        set { cloud.writeThrough(newValue, forKey: Keys.frameRate) }
    }

    var codec: VideoCodec {
        get { VideoCodec(rawValue: defaults.string(forKey: Keys.codec) ?? "") ?? .hevc }
        set { cloud.writeThrough(newValue.rawValue, forKey: Keys.codec) }
    }

    /// User-configured bitrate multiplier applied on top of the resolution's
    /// default bitrate (0.5 … 2.0). Default = 1.0.
    var bitrateMultiplier: Double {
        get {
            let value = defaults.double(forKey: Keys.bitrateMultiplier)
            return value > 0 ? value : 1.0
        }
        set { cloud.writeThrough(newValue.clamped(to: 0.5...2.0), forKey: Keys.bitrateMultiplier) }
    }

    var audioEnabled: Bool {
        get { defaults.object(forKey: Keys.audioEnabled) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.audioEnabled) }
    }

    var selectedCamera: CameraPosition {
        get { CameraPosition(rawValue: defaults.string(forKey: Keys.selectedCamera) ?? "") ?? .backWide }
        set { cloud.writeThrough(newValue.rawValue, forKey: Keys.selectedCamera) }
    }

    var segmentDuration: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.segmentDuration)
            return value > 0 ? value : AppConstants.defaultSegmentDuration
        }
        set { cloud.writeThrough(newValue, forKey: Keys.segmentDuration) }
    }

    // MARK: - Storage

    var storageCap: Int64 {
        get { defaults.object(forKey: Keys.storageCap) as? Int64 ?? AppConstants.defaultStorageCap }
        set { cloud.writeThrough(newValue, forKey: Keys.storageCap) }
    }

    var autoExportToPhotos: Bool {
        get { defaults.object(forKey: Keys.autoExportToPhotos) as? Bool ?? false }
        set { cloud.writeThrough(newValue, forKey: Keys.autoExportToPhotos) }
    }

    var iCloudBackupEnabled: Bool {
        get { defaults.bool(forKey: Keys.iCloudBackupEnabled) }
        set { cloud.writeThrough(newValue, forKey: Keys.iCloudBackupEnabled) }
    }

    // MARK: - Incident detection

    var incidentDetectionEnabled: Bool {
        get { defaults.object(forKey: Keys.incidentDetectionEnabled) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.incidentDetectionEnabled) }
    }

    var incidentSensitivity: IncidentSensitivity {
        get { IncidentSensitivity(rawValue: defaults.string(forKey: Keys.incidentSensitivity) ?? "") ?? .medium }
        set { cloud.writeThrough(newValue.rawValue, forKey: Keys.incidentSensitivity) }
    }

    var parkingSentryEnabled: Bool {
        get { defaults.bool(forKey: Keys.parkingSentryEnabled) }
        set { cloud.writeThrough(newValue, forKey: Keys.parkingSentryEnabled) }
    }

    var hardBrakeDetectionEnabled: Bool {
        get { defaults.object(forKey: Keys.hardBrakeDetectionEnabled) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.hardBrakeDetectionEnabled) }
    }

    // MARK: - Overlay (baked into exported MP4)

    var showSpeedOverlay: Bool {
        get { defaults.object(forKey: Keys.showSpeedOverlay) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.showSpeedOverlay) }
    }

    var showGPSOverlay: Bool {
        get { defaults.object(forKey: Keys.showGPSOverlay) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.showGPSOverlay) }
    }

    var showGForceOverlay: Bool {
        get { defaults.bool(forKey: Keys.showGForceOverlay) }
        set { cloud.writeThrough(newValue, forKey: Keys.showGForceOverlay) }
    }

    var watermarkEnabled: Bool {
        get { defaults.bool(forKey: Keys.watermarkEnabled) }
        set { cloud.writeThrough(newValue, forKey: Keys.watermarkEnabled) }
    }

    var watermarkText: String {
        get { defaults.string(forKey: Keys.watermarkText) ?? "CarCam Pro" }
        set { cloud.writeThrough(newValue, forKey: Keys.watermarkText) }
    }

    // MARK: - Behavior / display

    var autoStartOnLaunch: Bool {
        get { defaults.bool(forKey: Keys.autoStartOnLaunch) }
        set { cloud.writeThrough(newValue, forKey: Keys.autoStartOnLaunch) }
    }

    var dimDisplayWhileRecording: Bool {
        get { defaults.object(forKey: Keys.dimDisplayWhileRecording) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.dimDisplayWhileRecording) }
    }

    var allowThermalThrottling: Bool {
        get { defaults.object(forKey: Keys.allowThermalThrottling) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.allowThermalThrottling) }
    }

    var hapticsEnabled: Bool {
        get { defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.hapticsEnabled) }
    }

    // MARK: - Detection

    /// Enables the on-device police / emergency-vehicle detection subsystem.
    /// When false, frames skip the ML pipeline entirely.
    var policeDetectionEnabled: Bool {
        get { defaults.bool(forKey: Keys.policeDetectionEnabled) }
        set { cloud.writeThrough(newValue, forKey: Keys.policeDetectionEnabled) }
    }

    /// Whether to play an audible chime on confirmed detections.
    var detectionAudioEnabled: Bool {
        get { defaults.object(forKey: Keys.detectionAudioEnabled) as? Bool ?? true }
        set { cloud.writeThrough(newValue, forKey: Keys.detectionAudioEnabled) }
    }

    // MARK: - External-change signaling

    /// Called by `DependencyContainer` after `CloudSettingsStore` merges an
    /// external iCloud push into `UserDefaults`. `@Observable`'s property
    /// tracking is automatic for local writes (they go through stored
    /// properties' didSet equivalents), but an external `UserDefaults`
    /// mutation doesn't touch any of our @Observable surface — so we have
    /// to explicitly nudge observers to re-read.
    ///
    /// Implementation: we call `_$observationRegistrar.willSet` / `didSet`
    /// on every setting property whose key appears in `changedKeys` by
    /// round-tripping through the setter. Writing the *same* value via the
    /// setter is cheap (it re-writes the identical blob to UserDefaults +
    /// iCloud — effectively idempotent) and crucially fires the
    /// `@Observable` change signal.
    func notifyExternalChange(keys: [String]) {
        // Guard against a feedback loop: the setters below would normally
        // push the value back to iCloud, which would then fire another
        // change notification. Suppress the fan-out for the duration of
        // this merge — the value already matches iCloud's state.
        let previousSuppression = CloudSettingsStore.suppressFanOut
        CloudSettingsStore.suppressFanOut = true
        defer { CloudSettingsStore.suppressFanOut = previousSuppression }

        for key in keys {
            switch key {
            case Keys.resolution:                 self.resolution = self.resolution
            case Keys.frameRate:                  self.frameRate = self.frameRate
            case Keys.codec:                      self.codec = self.codec
            case Keys.bitrateMultiplier:          self.bitrateMultiplier = self.bitrateMultiplier
            case Keys.audioEnabled:               self.audioEnabled = self.audioEnabled
            case Keys.selectedCamera:             self.selectedCamera = self.selectedCamera
            case Keys.segmentDuration:            self.segmentDuration = self.segmentDuration
            case Keys.storageCap:                 self.storageCap = self.storageCap
            case Keys.autoExportToPhotos:         self.autoExportToPhotos = self.autoExportToPhotos
            case Keys.iCloudBackupEnabled:        self.iCloudBackupEnabled = self.iCloudBackupEnabled
            case Keys.incidentDetectionEnabled:   self.incidentDetectionEnabled = self.incidentDetectionEnabled
            case Keys.incidentSensitivity:        self.incidentSensitivity = self.incidentSensitivity
            case Keys.parkingSentryEnabled:       self.parkingSentryEnabled = self.parkingSentryEnabled
            case Keys.hardBrakeDetectionEnabled:  self.hardBrakeDetectionEnabled = self.hardBrakeDetectionEnabled
            case Keys.showSpeedOverlay:           self.showSpeedOverlay = self.showSpeedOverlay
            case Keys.showGPSOverlay:             self.showGPSOverlay = self.showGPSOverlay
            case Keys.showGForceOverlay:          self.showGForceOverlay = self.showGForceOverlay
            case Keys.watermarkEnabled:           self.watermarkEnabled = self.watermarkEnabled
            case Keys.watermarkText:              self.watermarkText = self.watermarkText
            case Keys.autoStartOnLaunch:          self.autoStartOnLaunch = self.autoStartOnLaunch
            case Keys.dimDisplayWhileRecording:   self.dimDisplayWhileRecording = self.dimDisplayWhileRecording
            case Keys.allowThermalThrottling:     self.allowThermalThrottling = self.allowThermalThrottling
            case Keys.hapticsEnabled:             self.hapticsEnabled = self.hapticsEnabled
            case Keys.policeDetectionEnabled:     self.policeDetectionEnabled = self.policeDetectionEnabled
            case Keys.detectionAudioEnabled:      self.detectionAudioEnabled = self.detectionAudioEnabled
            default:                              continue
            }
        }
    }

    // MARK: - Keys (private)

    /// Persistent key strings. `internal` rather than `private` so
    /// `AppSettings.notifyExternalChange` can reference them in its switch.
    enum Keys {
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
