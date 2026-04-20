import Foundation
import CoreLocation
import OSLog

protocol LocationServiceProtocol: Sendable {
    @MainActor func start() async
    @MainActor func stop()
    @MainActor var lastSample: LocationSample? { get }
    @MainActor var authorization: CLAuthorizationStatus { get }

    /// Observe location updates. Callback fires on the main actor.
    @MainActor func onUpdate(_ handler: @escaping @MainActor (LocationSample) -> Void)
}

/// `CLLocationManager` wrapper configured for continuous vehicle-grade
/// telemetry.
///
/// - Distance filter: 5 m (balances fix density vs. battery)
/// - Accuracy: `kCLLocationAccuracyBest`
/// - `allowsBackgroundLocationUpdates = true` (requires UIBackgroundModes:
///   location in Info.plist — already configured)
///
/// Speed samples can be negative when the fix is stale; the HUD should check
/// for this via `LocationSample.speedMPH?`.
@Observable
@MainActor
final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var handlers: [@MainActor (LocationSample) -> Void] = []

    private(set) var lastSample: LocationSample?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isUpdating: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func start() async {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isUpdating = true
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isUpdating = false
    }

    /// Upgrade to "Always" authorization — required for true background
    /// recording. Call only after the user has granted `whenInUse`.
    func requestAlwaysAuthorization() {
        guard manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    func enableBackgroundUpdates(_ enabled: Bool) {
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
    }

    func onUpdate(_ handler: @escaping @MainActor (LocationSample) -> Void) {
        handlers.append(handler)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let sample = LocationSample(from: last)
        Task { @MainActor in
            self.lastSample = sample
            for handler in self.handlers { handler(sample) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.ui.error("Location error: \(error.localizedDescription)")
    }
}
