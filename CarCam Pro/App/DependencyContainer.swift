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

    private(set) var settingsCoordinator: SettingsCoordinator?
    private(set) var storageManager: StorageManager?
    var modelContainer: ModelContainer?

    init() {
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
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let storage = StorageManager(modelContainer: modelContainer)
        self.storageManager = storage
        recordingEngine.configure(modelContainer: modelContainer, storageManager: storage)
        FileSystemManager.ensureBaseDirectoriesExist()

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
