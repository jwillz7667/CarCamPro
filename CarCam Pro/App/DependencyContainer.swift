import Foundation
import SwiftData
import Photos
import OSLog

/// Central wire-up for every long-lived service. The app creates a single
/// instance at launch and injects it into the environment; views read from it
/// via `@Environment(DependencyContainer.self)`.
@Observable
@MainActor
final class DependencyContainer {
    let cameraService: CameraService
    let recordingEngine: RecordingEngine
    let thermalMonitor: ThermalMonitor
    let incidentDetector: IncidentDetector
    let locationService: LocationService
    let settings: AppSettings
    let apiClient: APIClientProtocol

    private(set) var settingsCoordinator: SettingsCoordinator?
    private(set) var storageManager: StorageManager?
    var modelContainer: ModelContainer?

    init(apiClient: APIClientProtocol = APIClient()) {
        let camera = CameraService()
        let thermal = ThermalMonitor()
        let incident = IncidentDetector()
        let location = LocationService()

        self.cameraService = camera
        self.thermalMonitor = thermal
        self.incidentDetector = incident
        self.locationService = location
        self.recordingEngine = RecordingEngine(cameraService: camera)
        self.settings = .shared
        self.apiClient = apiClient
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let storage = StorageManager(modelContainer: modelContainer)
        self.storageManager = storage
        recordingEngine.configure(modelContainer: modelContainer, storageManager: storage)
        FileSystemManager.ensureBaseDirectoriesExist()

        // Boot iCloud settings roaming BEFORE any service reads a
        // preference. The bootstrap merges remote state into local
        // UserDefaults synchronously, so the subsequent
        // `settings.iCloudBackupEnabled` / `settings.incidentSensitivity`
        // reads below see the user's roamed values, not stale defaults
        // from a fresh install.
        CloudSettingsStore.shared.bootstrap { [weak self] changedKeys in
            guard let self else { return }
            self.handleExternalSettingsChange(changedKeys)
        }

        // Storage cap enforcement is wired through the shim gate so the
        // SettingsCoordinator can trigger it without holding a ModelContainer.
        StorageEnforcementGate.enforceAction = { @Sendable [weak storage] in
            try await storage?.enforceStorageCap()
        }

        let coordinator = SettingsCoordinator(
            settings: .shared,
            camera: cameraService,
            incident: incidentDetector,
            thermal: thermalMonitor,
            recording: recordingEngine
        )
        self.settingsCoordinator = coordinator

        // Apply persisted iCloud backup preference on first run.
        coordinator.setiCloudBackup(settings.iCloudBackupEnabled)

        // Seed the detection subsystem with the persisted preference.
        PoliceDetectionSystem.shared.setEnabled(settings.policeDetectionEnabled)

        // Start long-running services.
        thermalMonitor.start()
        Task { @MainActor in
            await locationService.start()
        }
        Task {
            if settings.incidentDetectionEnabled {
                try? await incidentDetector.start()
                await incidentDetector.setThreshold(settings.incidentSensitivity.threshold)
            }
        }

        recordingEngine.setParkingSentryEnabled(settings.parkingSentryEnabled)

        // Wire thermal tier → recording engine + incident detector.
        thermalMonitor.onTierChange { [weak self] tier in
            guard let self else { return }
            if self.settings.allowThermalThrottling {
                self.recordingEngine.applyThermalTier(tier)
                Task { await self.incidentDetector.setSampleRateHz(tier.incidentSampleRateHz) }
            }
        }

        // Wire incident events → protect current clip + auto-export.
        Task { [weak self] in
            guard let self else { return }
            let events = await self.incidentDetector.events()
            for await event in events {
                await MainActor.run {
                    self.recordingEngine.handleIncident(event)
                    if self.settings.autoExportToPhotos {
                        Task { await self.exportLatestLockedClip() }
                    }
                }
            }
        }

        // Wire location samples → recording metadata.
        locationService.onUpdate { [weak self] sample in
            self?.recordingEngine.ingestLocation(sample)
        }
    }

    // MARK: - iCloud settings sync

    /// Called from `CloudSettingsStore.bootstrap`'s observer when another
    /// device on the same Apple ID pushes a settings change via iCloud KVS.
    ///
    /// Two responsibilities:
    ///   1. Re-fire the `@Observable` signal on `AppSettings` so every
    ///      bound SwiftUI view redraws with the new value.
    ///   2. Re-invoke the `SettingsCoordinator` side-effects tied to each
    ///      key — e.g. if the sensitivity changed remotely, the incident
    ///      detector's in-memory threshold is stale and must be updated.
    private func handleExternalSettingsChange(_ changedKeys: [String]) {
        settings.notifyExternalChange(keys: changedKeys)
        guard let coordinator = settingsCoordinator else { return }

        for key in changedKeys {
            switch key {
            case "resolution", "frameRate", "codec", "bitrateMultiplier",
                 "audioEnabled", "selectedCamera":
                coordinator.applyCameraConfiguration()
            case "incidentSensitivity":
                coordinator.applyIncidentThreshold()
            case "incidentDetectionEnabled":
                Task { [settings, coordinator] in
                    await coordinator.applyIncidentDetection(enabled: settings.incidentDetectionEnabled)
                }
            case "storageCap":
                coordinator.applyStorageCap()
            case "dimDisplayWhileRecording":
                coordinator.applyDisplayDimming()
            case "iCloudBackupEnabled":
                coordinator.setiCloudBackup(settings.iCloudBackupEnabled)
            case "autoExportToPhotos":
                coordinator.applyPhotosAuthorization()
            case "policeDetectionEnabled":
                PoliceDetectionSystem.shared.setEnabled(settings.policeDetectionEnabled)
            case "parkingSentryEnabled":
                recordingEngine.setParkingSentryEnabled(settings.parkingSentryEnabled)
            default:
                // Purely-UI preferences (overlays, haptics, watermark) need no
                // coordinator call — the next redraw reads them directly.
                continue
            }
        }
    }

    // MARK: - Auto-export

    /// Copy the most recently-protected clip for the active session into the
    /// user's Photos library. Requires `.addOnly` authorization.
    private func exportLatestLockedClip() async {
        guard let modelContainer else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }

        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<VideoClip>(
            predicate: #Predicate<VideoClip> { clip in clip.isProtected == true },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else { return }
        let url = latest.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            AppLogger.storage.info("Exported \(latest.fileName) to Photos")
        } catch {
            AppLogger.storage.error("Photos export failed: \(error.localizedDescription)")
        }
    }
}
