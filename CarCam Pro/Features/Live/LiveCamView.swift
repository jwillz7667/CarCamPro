import SwiftUI
import AVFoundation

/// LIVE tab — full-bleed camera preview in landscape with a comprehensive HUD
/// (matches `LiveCamView` + `LiveHUD` from the mockup). Locks to landscape via
/// a UIHostingController wrapper so system rotation isn't required.
struct LiveCamView: View {
    @Environment(DependencyContainer.self) private var container
    @Binding var activeTab: CCTab

    @State private var hud = LiveHUDState()
    @State private var authorized = false
    @State private var permissionChecked = false
    @State private var gForceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            CCTheme.void.ignoresSafeArea()

            if authorized {
                CameraPreviewView(session: container.cameraService.captureSession)
                    .ignoresSafeArea()
                    .overlay(ScanLine())
                    .overlay(LiveHUDOverlay(hud: hud,
                                            isRecording: container.recordingEngine.state.isRecording,
                                            duration: container.recordingEngine.formattedDuration,
                                            onLock: lockCurrent,
                                            onStop: stopRecording))
            } else if permissionChecked {
                cameraDeniedView
            } else {
                ProgressView().tint(.white)
            }
        }
        .task { await setupCamera() }
        .task(id: container.recordingEngine.state.isRecording) {
            await observeGForce()
        }
        .onDisappear {
            gForceTask?.cancel()
        }
    }

    // MARK: - Setup

    private func setupCamera() async {
        let ok = await CameraService.checkAuthorization()
        authorized = ok
        permissionChecked = true
        guard ok else { return }

        if !container.cameraService.isRunning {
            try? await container.cameraService.configure(CameraConfiguration.default)
            try? await container.cameraService.startCapture()
        }

        // Pipe location samples into the HUD every time they update.
        container.locationService.onUpdate { sample in
            updateHUD(from: sample)
        }
        if let last = container.locationService.lastSample {
            updateHUD(from: last)
        }
    }

    private func updateHUD(from sample: LocationSample) {
        if let mph = sample.speedMPH {
            hud.speedMPH = max(0, mph)
        }
        if sample.courseDegrees >= 0 {
            hud.heading = sample.courseDegrees
            hud.compass = sample.compass ?? ""
        }
        hud.altitudeFeet = Int(sample.altitudeMeters * 3.28084)
        hud.coordinateLabel = String(format: "%.4f° %@ · %.4f° %@",
                                     abs(sample.latitude),
                                     sample.latitude >= 0 ? "N" : "S",
                                     abs(sample.longitude),
                                     sample.longitude >= 0 ? "E" : "W")
        hud.currentBufferSeconds = container.recordingEngine.currentDuration
    }

    private func observeGForce() async {
        gForceTask?.cancel()
        gForceTask = Task { @MainActor in
            let stream = await container.incidentDetector.liveGForce()
            for await sample in stream {
                guard !Task.isCancelled else { break }
                hud.totalG = sample.total
                hud.peakG = max(hud.peakG, sample.total)
                hud.gAxisX = sample.x
                hud.gAxisY = sample.y
            }
        }
    }

    // MARK: - Actions

    private func lockCurrent() {
        Task { await container.recordingEngine.protectCurrentClip() }
    }

    private func stopRecording() {
        Task {
            try? await container.recordingEngine.stopRecording()
            activeTab = .home
        }
    }

    // MARK: - Views

    private var cameraDeniedView: some View {
        VStack(spacing: 20) {
            ApertureMark(size: 48, color: CCTheme.amber)
            Text("Camera Access Required")
                .font(CCFont.display(22, weight: .regular))
                .foregroundStyle(CCTheme.ink)
            Text("Enable camera access in Settings to record driving footage.")
                .font(CCFont.sans(14))
                .foregroundStyle(CCTheme.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("OPEN SETTINGS") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(CCFont.mono(11, weight: .medium))
            .kerning(2.2)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
            .foregroundStyle(CCTheme.ink)
            .padding(.top, 8)
        }
    }
}

/// Subtle amber scan line, sweeping top→bottom. Purely cosmetic (matches mock).
private struct ScanLine: View {
    @State private var offset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, CCTheme.amber.opacity(0.07), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .offset(y: offset * (geo.size.height + 60))
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    offset = 2.0
                }
            }
        }
        .allowsHitTesting(false)
    }
}
