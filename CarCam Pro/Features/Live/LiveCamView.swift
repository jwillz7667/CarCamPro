import SwiftUI
import AVFoundation

/// LIVE tab — full-bleed camera preview with a minimal Liquid Glass overlay.
///
/// Only the controls a driver actually needs while moving:
///   - A single REC + timecode pill at the top (status, glanceable).
///   - A speed pill in the opposite corner (optional, driven by GPS).
///   - Three floating glass controls at the bottom:
///     flip-camera · REC / STOP shutter · LOCK clip.
///
/// Everything else from earlier iterations (velocity gauge, G-force target,
/// horizon, heading/altitude, coordinate labels) has been moved off this
/// screen. Those readouts live on the Home dashboard + incident playback.
struct LiveCamView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var authorized = false
    @State private var permissionChecked = false
    @State private var currentSpeedMPH: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if authorized {
                CameraPreviewView(session: container.cameraService.captureSession)
                    .ignoresSafeArea()
            } else if permissionChecked {
                cameraDeniedView
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if authorized {
                DetectionOverlayView()
                    .ignoresSafeArea()
                overlay
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await setupCamera() }
        .onChange(of: container.recordingEngine.state.isRecording) { _, isOn in
            if isOn {
                container.settingsCoordinator?.applyDisplayDimming()
            } else {
                container.settingsCoordinator?.restoreDisplay()
            }
        }
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, CCTheme.Space.lg)
                .padding(.top, CCTheme.Space.sm)

            Spacer(minLength: 0)

            bottomControls
                .padding(.horizontal, CCTheme.Space.lg)
                .padding(.bottom, CCTheme.Space.xl)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            if container.recordingEngine.state.isRecording {
                recPill
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if let speed = currentSpeedMPH {
                speedPill(speed)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: container.recordingEngine.state.isRecording)
        .animation(.snappy, value: currentSpeedMPH)
    }

    private var recPill: some View {
        GlassStatusPill {
            HStack(spacing: 8) {
                Circle()
                    .fill(CCTheme.red)
                    .frame(width: 8, height: 8)
                    .symbolEffect(.pulse, options: .repeating)
                Text("REC")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CCTheme.red)
                Text(container.recordingEngine.formattedDuration)
                    .font(CCFont.mono(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.default, value: container.recordingEngine.currentDuration)
            }
        }
    }

    private func speedPill(_ mph: Int) -> some View {
        GlassStatusPill {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(mph)")
                    .font(CCFont.mono(20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("mph")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var bottomControls: some View {
        HStack {
            GlassIconButton(systemImage: "camera.rotate", size: 52) {
                flipCamera()
            }

            Spacer()

            shutterButton

            Spacer()

            GlassIconButton(
                systemImage: "lock.fill",
                size: 52,
                style: .tinted(CCTheme.amber)
            ) {
                lockClip()
            }
            .disabled(!container.recordingEngine.state.isRecording)
            .opacity(container.recordingEngine.state.isRecording ? 1 : 0.4)
        }
    }

    /// Centered shutter — white ring + red inner circle, transforms to a red
    /// stop-square while recording. Pure SwiftUI, no glyphs, no letter spacing.
    private var shutterButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 4)
                    .frame(width: 78, height: 78)

                if container.recordingEngine.state.isRecording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CCTheme.red)
                        .frame(width: 34, height: 34)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(CCTheme.red)
                        .frame(width: 64, height: 64)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .heavy),
                         trigger: container.recordingEngine.state.isRecording)
        .animation(.snappy, value: container.recordingEngine.state.isRecording)
    }

    // MARK: - Camera permission denied

    private var cameraDeniedView: some View {
        VStack(spacing: CCTheme.Space.lg) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Text("Camera access required")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Enable camera access in Settings to record driving footage.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, CCTheme.Space.xl)

            GlassPillButton(style: .prominent, action: openSettings) {
                Text("Open Settings")
            }
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        Task {
            if container.recordingEngine.state.isRecording {
                try? await container.recordingEngine.stopRecording()
            } else {
                try? await container.recordingEngine.startRecording()
            }
        }
    }

    private func flipCamera() {
        let next: CameraPosition = container.settings.selectedCamera == .backWide ? .front : .backWide
        Task { await container.settingsCoordinator?.setSelectedCamera(next) }
    }

    private func lockClip() {
        Task { await container.recordingEngine.protectCurrentClip() }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Camera setup

    private func setupCamera() async {
        let ok = await CameraService.checkAuthorization()
        authorized = ok
        permissionChecked = true
        guard ok else { return }

        if !container.cameraService.isRunning {
            try? await container.cameraService.configure(CameraConfiguration.default)
            try? await container.cameraService.startCapture()
        }

        container.locationService.onUpdate { sample in
            if let mph = sample.speedMPH, mph >= 1 {
                currentSpeedMPH = Int(mph.rounded())
            } else {
                currentSpeedMPH = nil
            }
        }
        if let last = container.locationService.lastSample,
           let mph = last.speedMPH, mph >= 1 {
            currentSpeedMPH = Int(mph.rounded())
        }
    }
}
