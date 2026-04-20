import Foundation
import SwiftData

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
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let storage = StorageManager(modelContainer: modelContainer)
        self.storageManager = storage
        recordingEngine.configure(modelContainer: modelContainer, storageManager: storage)
        FileSystemManager.ensureBaseDirectoriesExist()

        // Start long-running services.
        thermalMonitor.start()
        Task { @MainActor in
            await locationService.start()
        }
        Task {
            try? await incidentDetector.start()
        }

        // Wire thermal tier → recording engine + incident detector.
        thermalMonitor.onTierChange { [weak self] tier in
            guard let self else { return }
            self.recordingEngine.applyThermalTier(tier)
            Task { await self.incidentDetector.setSampleRateHz(tier.incidentSampleRateHz) }
        }

        // Wire incident events → protect current clip.
        Task { [weak self] in
            guard let self else { return }
            let events = await self.incidentDetector.events()
            for await event in events {
                await MainActor.run {
                    self.recordingEngine.handleIncident(event)
                }
            }
        }

        // Wire location samples → recording metadata.
        locationService.onUpdate { [weak self] sample in
            self?.recordingEngine.ingestLocation(sample)
        }
    }
}
