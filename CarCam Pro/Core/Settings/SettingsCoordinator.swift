import Foundation
import Observation
import UIKit
import Photos
import OSLog

/// Bridges `AppSettings` mutations to the services that must react to them.
///
/// Each public method mutates one preference, persists it, and applies the
/// corresponding side-effect — e.g. changing the capture resolution triggers
/// a `CameraService.configure(...)` call with a fresh `CameraConfiguration`,
/// changing the incident threshold pushes the new value into the
/// `IncidentDetector` actor, etc.
///
/// Views bind their controls to methods on this coordinator rather than
/// mutating `AppSettings` directly — that keeps the "apply the effect"
/// logic in one place and lets the settings UI stay a dumb, functional Form.
@Observable
@MainActor
final class SettingsCoordinator {
    private let settings: AppSettings
    private let camera: CameraService
    private let incident: IncidentDetector
    private let thermal: ThermalMonitor
    private let recording: RecordingEngine

    init(
        settings: AppSettings = .shared,
        camera: CameraService,
        incident: IncidentDetector,
        thermal: ThermalMonitor,
        recording: RecordingEngine
    ) {
        self.settings = settings
        self.camera = camera
        self.incident = incident
        self.thermal = thermal
        self.recording = recording
    }

    // MARK: - Capture

    /// Change capture resolution. If a recording is in progress the change is
    /// queued; otherwise the camera is reconfigured immediately.
    func setResolution(_ resolution: VideoResolution) {
        guard resolution != settings.resolution else { return }
        settings.resolution = resolution
        reconfigureCameraIfIdle()
    }

    func setFrameRate(_ fps: Int) {
        guard fps != settings.frameRate else { return }
        settings.frameRate = fps
        reconfigureCameraIfIdle()
    }

    func setCodec(_ codec: VideoCodec) {
        guard codec != settings.codec else { return }
        settings.codec = codec
        reconfigureCameraIfIdle()
    }

    func setBitrateMultiplier(_ value: Double) {
        settings.bitrateMultiplier = value
        camera.applyThermalPolicy(
            maxFrameRate: settings.frameRate,
            bitrateMultiplier: value * thermal.currentTier.bitrateMultiplier,
            forcedResolutionCeiling: thermal.currentTier.forcedResolutionCeiling
        )
    }

    func setAudioEnabled(_ enabled: Bool) {
        settings.audioEnabled = enabled
        reconfigureCameraIfIdle()
    }

    func setSelectedCamera(_ position: CameraPosition) async {
        settings.selectedCamera = position
        guard !recording.state.isRecording else { return }
        try? await camera.switchCamera(to: position)
    }

    func setSegmentDuration(_ duration: TimeInterval) {
        settings.segmentDuration = duration
        // Applied on next rotation by SegmentManager reading AppSettings at
        // segment-start time — no explicit apply needed.
    }

    // MARK: - Storage

    func setStorageCap(_ bytes: Int64) {
        settings.storageCap = bytes
        Task.detached { [recording] in
            _ = recording
            try? await StorageEnforcementGate.enforce()
        }
    }

    func setAutoExportToPhotos(_ enabled: Bool) async {
        settings.autoExportToPhotos = enabled
        guard enabled else { return }
        // Proactively request authorization so the user sees the system
        // prompt at the moment of toggling, not on first clip lock.
        _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    func setiCloudBackup(_ enabled: Bool) {
        settings.iCloudBackupEnabled = enabled
        // Toggles the `.isExcludedFromBackup` resource value on the
        // recordings directory. Each new file inherits this at creation.
        var url = FileSystemManager.recordingsBaseURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = !enabled
        try? url.setResourceValues(values)
    }

    // MARK: - Incident

    func setIncidentDetection(_ enabled: Bool) async {
        settings.incidentDetectionEnabled = enabled
        if enabled {
            try? await incident.start()
            await incident.setThreshold(settings.incidentSensitivity.threshold)
        } else {
            await incident.stop()
        }
    }

    func setIncidentSensitivity(_ sensitivity: IncidentSensitivity) async {
        settings.incidentSensitivity = sensitivity
        await incident.setThreshold(sensitivity.threshold)
    }

    func setParkingSentry(_ enabled: Bool) {
        settings.parkingSentryEnabled = enabled
        recording.setParkingSentryEnabled(enabled)
    }

    func setHardBrakeDetection(_ enabled: Bool) {
        settings.hardBrakeDetectionEnabled = enabled
    }

    // MARK: - Overlay

    func setShowSpeedOverlay(_ enabled: Bool)  { settings.showSpeedOverlay = enabled }
    func setShowGPSOverlay(_ enabled: Bool)    { settings.showGPSOverlay = enabled }
    func setShowGForceOverlay(_ enabled: Bool) { settings.showGForceOverlay = enabled }

    func setWatermarkEnabled(_ enabled: Bool)  { settings.watermarkEnabled = enabled }
    func setWatermarkText(_ text: String)      { settings.watermarkText = text }

    // MARK: - Behavior / display

    func setAutoStartOnLaunch(_ enabled: Bool) { settings.autoStartOnLaunch = enabled }
    func setHapticsEnabled(_ enabled: Bool)    { settings.hapticsEnabled = enabled }

    // MARK: - Detection

    func setPoliceDetectionEnabled(_ enabled: Bool) {
        settings.policeDetectionEnabled = enabled
        PoliceDetectionSystem.shared.setEnabled(enabled)
    }

    func setDetectionAudioEnabled(_ enabled: Bool) {
        settings.detectionAudioEnabled = enabled
    }

    func setDimDisplayWhileRecording(_ enabled: Bool) {
        settings.dimDisplayWhileRecording = enabled
        if recording.state.isRecording {
            applyDisplayDimming()
        }
    }

    func setAllowThermalThrottling(_ enabled: Bool) {
        settings.allowThermalThrottling = enabled
        // When disabled, clamp the monitor to Nominal policy by replaying
        // the current raw state through the recording engine at nominal.
        if !enabled {
            recording.applyThermalTier(.nominal)
        } else {
            recording.applyThermalTier(thermal.currentTier)
        }
    }

    /// Apply the display-brightness policy on demand — called by the live
    /// HUD when recording begins.
    func applyDisplayDimming() {
        guard settings.dimDisplayWhileRecording else { return }
        let tier = settings.allowThermalThrottling ? thermal.currentTier : .nominal
        UIScreen.main.brightness = tier.brightnessFactor
    }

    /// Restore the system brightness control on recording stop.
    func restoreDisplay() {
        // `UIScreen.brightness` has no "system value" to restore to — we
        // bump it back to mid (0.5) and let the system take over again.
        UIScreen.main.brightness = 0.5
    }

    // MARK: - Utility

    func resetAllSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "Res.CarCam-Pro"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        AppLogger.ui.notice("Settings reset to defaults")
    }

    // MARK: - Private

    private func reconfigureCameraIfIdle() {
        guard !recording.state.isRecording else {
            AppLogger.ui.info("Capture setting changed during recording — will apply on next session")
            return
        }
        Task {
            try? await camera.configure(CameraConfiguration.default)
            if !camera.isRunning {
                try? await camera.startCapture()
            }
        }
    }
}

/// Pinhole shim — `StorageManager` needs a model-container reference to
/// enforce the cap, and the coordinator doesn't own one. This gate is filled
/// in by `DependencyContainer` at launch.
enum StorageEnforcementGate {
    nonisolated(unsafe) static var enforceAction: (@Sendable () async throws -> Void)?

    static func enforce() async throws {
        try await enforceAction?()
    }
}
