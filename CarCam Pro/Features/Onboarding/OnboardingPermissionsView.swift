import SwiftUI
import AVFoundation
import CoreLocation
import CoreMotion
import Photos

enum OnboardingPermission: String, CaseIterable, Identifiable {
    case camera, location, motion, microphone, photos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera:     return "Camera"
        case .location:   return "Location"
        case .motion:     return "Motion"
        case .microphone: return "Microphone"
        case .photos:     return "Photos"
        }
    }

    var subtitle: String {
        switch self {
        case .camera:     return "Record video while driving."
        case .location:   return "GPS speed, heading, and clip geotagging."
        case .motion:     return "Detect impacts and hard braking."
        case .microphone: return "Capture audio with your footage."
        case .photos:     return "Save locked incident clips to your library."
        }
    }

    var symbol: String {
        switch self {
        case .camera:     return "camera.fill"
        case .location:   return "location.fill"
        case .motion:     return "waveform.path.ecg"
        case .microphone: return "mic.fill"
        case .photos:     return "photo.fill"
        }
    }
}

enum PermissionStatus: Equatable {
    case pending, granted, denied
}

struct OnboardingPermissionsView: View {
    let onContinue: () -> Void

    @State private var statuses: [OnboardingPermission: PermissionStatus] = [:]
    @State private var motionManager = CMMotionManager()
    @State private var locationDelegate: PermissionsLocationDelegate?

    var body: some View {
        OnboardingFrame(step: 2) {
            OnboardingTitle(
                eyebrow: "Authorizations",
                title: "Grant access",
                subtitle: "CarCam Pro only requests what it needs. You can change any of these later in iOS Settings."
            )

            VStack(spacing: CCTheme.Space.md) {
                ForEach(OnboardingPermission.allCases) { perm in
                    PermissionCard(
                        permission: perm,
                        status: statuses[perm] ?? .pending
                    )
                }
            }
        } footer: {
            OnboardingPrimaryButton(title: "Authorize All") {
                Task { await requestAll() }
            }
            OnboardingSecondaryButton(title: "Continue") {
                onContinue()
            }
        }
        .task { refreshStatuses() }
    }

    // MARK: - Status refresh

    private func refreshStatuses() {
        statuses[.camera] = mapAV(AVCaptureDevice.authorizationStatus(for: .video))
        statuses[.microphone] = mapAV(AVCaptureDevice.authorizationStatus(for: .audio))
        statuses[.location] = mapLocation(CLLocationManager().authorizationStatus)
        statuses[.motion] = .pending
        statuses[.photos] = mapPhotos(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    private func requestAll() async {
        let cam = await AVCaptureDevice.requestAccess(for: .video)
        statuses[.camera] = cam ? .granted : .denied

        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        statuses[.microphone] = mic ? .granted : .denied

        await requestLocation()
        await requestMotion()

        let photos = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        statuses[.photos] = mapPhotos(photos)

        // If the critical permissions are granted, auto-advance. Otherwise
        // the user can tap "Continue" to move on without them.
        if statuses[.camera] == .granted &&
           statuses[.location] == .granted &&
           statuses[.motion] == .granted {
            onContinue()
        }
    }

    private func requestLocation() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let delegate = PermissionsLocationDelegate { status in
                statuses[.location] = mapLocation(status)
                cont.resume()
            }
            locationDelegate = delegate
            delegate.start()
        }
    }

    private func requestMotion() async {
        guard motionManager.isAccelerometerAvailable else {
            statuses[.motion] = .denied
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            motionManager.startAccelerometerUpdates(to: .main) { _, error in
                motionManager.stopAccelerometerUpdates()
                statuses[.motion] = error == nil ? .granted : .denied
                cont.resume()
            }
        }
    }

    // MARK: - Helpers

    private func mapAV(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .pending
        @unknown default: return .pending
        }
    }

    private func mapLocation(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .pending
        @unknown default: return .pending
        }
    }

    private func mapPhotos(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .limited: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .pending
        @unknown default: return .pending
        }
    }
}

// MARK: - Row card

private struct PermissionCard: View {
    let permission: OnboardingPermission
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: CCTheme.Space.md) {
            Image(systemName: permission.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(CCTheme.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CCTheme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(permission.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            statusBadge
        }
        .padding(CCTheme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: CCTheme.radiusLarge, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var statusBadge: some View {
        Group {
            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(CCTheme.green)
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            case .pending:
                Image(systemName: "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Tiny delegate adapter so `requestWhenInUseAuthorization()` works with
/// async/await — CLLocationManager reports status via delegate callback.
private final class PermissionsLocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let onComplete: (CLAuthorizationStatus) -> Void
    private var hasResolved = false

    init(onComplete: @escaping (CLAuthorizationStatus) -> Void) {
        self.onComplete = onComplete
        super.init()
        manager.delegate = self
    }

    @MainActor
    func start() {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            resolve(status)
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        resolve(status)
    }

    private func resolve(_ status: CLAuthorizationStatus) {
        guard !hasResolved else { return }
        hasResolved = true
        onComplete(status)
    }
}
