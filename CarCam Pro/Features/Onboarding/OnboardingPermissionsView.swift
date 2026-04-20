import SwiftUI
import AVFoundation
import CoreLocation
import CoreMotion
import Photos

/// Permission item — maps to an iOS system API call.
enum OnboardingPermission: String, CaseIterable, Identifiable {
    case camera, location, motion, microphone, photos

    var id: String { rawValue }

    var code: String {
        switch self {
        case .camera:     return "CAM"
        case .location:   return "LOC"
        case .motion:     return "MOT"
        case .microphone: return "MIC"
        case .photos:     return "PHO"
        }
    }

    var label: String {
        switch self {
        case .camera:     return "Camera"
        case .location:   return "Location (Always)"
        case .motion:     return "Motion & Orientation"
        case .microphone: return "Microphone"
        case .photos:     return "Photos"
        }
    }

    var subtitle: String {
        switch self {
        case .camera:     return "Required for video capture."
        case .location:   return "GPS, speed, and trip geofencing."
        case .motion:     return "G-force and impact detection."
        case .microphone: return "Optional — for voice memos."
        case .photos:     return "To save locked clips to library."
        }
    }

    var required: Bool {
        self == .camera || self == .location || self == .motion
    }
}

enum PermissionStatus: Equatable {
    case pending
    case granted
    case denied
    case skipped
}

struct OnboardingPermissionsView: View {
    @State private var statuses: [OnboardingPermission: PermissionStatus] = [:]
    @State private var motionManager = CMMotionManager()
    @State private var locationDelegate: PermissionsLocationDelegate?
    let onContinue: () -> Void

    var body: some View {
        OnboardingFrame(step: 2) {
            VStack(alignment: .leading, spacing: 0) {
                CCLabel("02 — Authorizations", size: 10, color: CCTheme.amber)
                    .padding(.bottom, 8)

                Text("Grant the sensors\nCarCam needs.")
                    .font(CCFont.display(30, weight: .light))
                    .kerning(-0.6)
                    .foregroundStyle(CCTheme.ink)
                    .padding(.bottom, 36)

                VStack(spacing: 0) {
                    Rectangle().fill(CCTheme.rule).frame(height: 1)
                    ForEach(OnboardingPermission.allCases) { perm in
                        PermissionRow(
                            permission: perm,
                            status: statuses[perm] ?? .pending
                        )
                        Rectangle().fill(CCTheme.rule).frame(height: 1)
                    }
                }

                Spacer(minLength: 24)

                OnboardingButton(title: "Authorize all", primary: true) {
                    Task { await requestAll() }
                }
                OnboardingButton(title: "Continue") {
                    onContinue()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 110)
            .padding(.bottom, 90)
        }
        .task { refreshStatuses() }
    }

    // MARK: - Permission logic

    private func refreshStatuses() {
        statuses[.camera] = mapAV(AVCaptureDevice.authorizationStatus(for: .video))
        statuses[.microphone] = mapAV(AVCaptureDevice.authorizationStatus(for: .audio))
        statuses[.location] = mapLocation(CLLocationManager().authorizationStatus)
        statuses[.motion] = .pending
        statuses[.photos] = mapPhotos(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    private func requestAll() async {
        // Camera
        let cam = await AVCaptureDevice.requestAccess(for: .video)
        statuses[.camera] = cam ? .granted : .denied

        // Microphone
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        statuses[.microphone] = mic ? .granted : .denied

        // Location — CLLocationManager requires delegate callbacks.
        await requestLocation()

        // Motion — pinging with a one-shot query is the only supported trigger.
        await requestMotion()

        // Photos (add-only)
        let p = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        statuses[.photos] = mapPhotos(p)
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

private struct PermissionRow: View {
    let permission: OnboardingPermission
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: 16) {
            CCLabel(permission.code, size: 10, color: CCTheme.ink3)
                .frame(width: 32, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.label)
                    .font(CCFont.sans(15))
                    .foregroundStyle(CCTheme.ink)
                Text(permission.subtitle)
                    .font(CCFont.sans(12))
                    .foregroundStyle(CCTheme.ink3)
            }

            Spacer()

            StatusBadge(status: status, required: permission.required)
        }
        .padding(.vertical, 18)
    }
}

private struct StatusBadge: View {
    let status: PermissionStatus
    let required: Bool

    private var palette: (Color, String) {
        switch status {
        case .granted: return (CCTheme.green, "✓ OK")
        case .pending: return (CCTheme.amber, "AUTH")
        case .denied:  return (CCTheme.red, required ? "FAIL" : "SKIP")
        case .skipped: return (CCTheme.ink4, "SKIP")
        }
    }

    var body: some View {
        Text(palette.1)
            .font(CCFont.mono(9, weight: .medium))
            .kerning(1.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(palette.0)
            .overlay(Rectangle().stroke(palette.0, lineWidth: 1))
    }
}

/// Small adapter class needed because `CLLocationManager` callbacks are
/// delegate-based; `requestWhenInUseAuthorization()` doesn't return.
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
            complete(with: status)
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        complete(with: status)
    }

    private func complete(with status: CLAuthorizationStatus) {
        guard !hasResolved else { return }
        hasResolved = true
        onComplete(status)
    }
}
