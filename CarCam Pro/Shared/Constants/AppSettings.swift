import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var resolution: VideoResolution {
        get { VideoResolution(rawValue: defaults.string(forKey: "resolution") ?? "") ?? .hd1080 }
        set { defaults.set(newValue.rawValue, forKey: "resolution") }
    }

    var frameRate: Int {
        get {
            let value = defaults.integer(forKey: "frameRate")
            return value > 0 ? value : 30
        }
        set { defaults.set(newValue, forKey: "frameRate") }
    }

    var codec: VideoCodec {
        get { VideoCodec(rawValue: defaults.string(forKey: "codec") ?? "") ?? .hevc }
        set { defaults.set(newValue.rawValue, forKey: "codec") }
    }

    var audioEnabled: Bool {
        get { defaults.object(forKey: "audioEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "audioEnabled") }
    }

    var selectedCamera: CameraPosition {
        get { CameraPosition(rawValue: defaults.string(forKey: "selectedCamera") ?? "") ?? .backWide }
        set { defaults.set(newValue.rawValue, forKey: "selectedCamera") }
    }

    var segmentDuration: TimeInterval {
        get {
            let value = defaults.double(forKey: "segmentDuration")
            return value > 0 ? value : AppConstants.defaultSegmentDuration
        }
        set { defaults.set(newValue, forKey: "segmentDuration") }
    }

    var storageCap: Int64 {
        get {
            let value = defaults.object(forKey: "storageCap") as? Int64
            return value ?? AppConstants.defaultStorageCap
        }
        set { defaults.set(newValue, forKey: "storageCap") }
    }

    var incidentDetectionEnabled: Bool {
        get { defaults.object(forKey: "incidentDetectionEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "incidentDetectionEnabled") }
    }

    var incidentSensitivity: IncidentSensitivity {
        get { IncidentSensitivity(rawValue: defaults.string(forKey: "incidentSensitivity") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "incidentSensitivity") }
    }

    var autoStartOnLaunch: Bool {
        get { defaults.bool(forKey: "autoStartOnLaunch") }
        set { defaults.set(newValue, forKey: "autoStartOnLaunch") }
    }

    var dimDisplayWhileRecording: Bool {
        get { defaults.object(forKey: "dimDisplayWhileRecording") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dimDisplayWhileRecording") }
    }

    var allowThermalThrottling: Bool {
        get { defaults.object(forKey: "allowThermalThrottling") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "allowThermalThrottling") }
    }

    private init() {}
}
