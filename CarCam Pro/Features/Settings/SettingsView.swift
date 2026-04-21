import SwiftUI
import SwiftData

/// SETTINGS tab — a native SwiftUI `Form` where every control is functional:
///   - Pickers persist to `AppSettings` and drive `SettingsCoordinator` to
///     push the new value into the relevant service (camera reconfig,
///     incident threshold, storage cap enforcement, etc.).
///   - Toggles bind to the same coordinator and trigger side-effects (e.g.
///     requesting Photos authorization the first time auto-export is enabled).
///
/// No manual "apply" step — every change is live.
struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container

    // Storage info is recomputed on-demand — not persisted.
    @State private var storageUsedBytes: Int64 = 0
    @State private var deviceFreeBytes: Int64 = 0
    @State private var lockedBytes: Int64 = 0
    @State private var showResetConfirm = false

    private var settings: AppSettings { container.settings }
    private var coord: SettingsCoordinator? { container.settingsCoordinator }

    var body: some View {
        NavigationStack {
            Form {
                captureSection
                detectionSection
                incidentSection
                overlaySection
                storageSection
                recordingBehaviorSection
                thermalSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task { await refreshStorage() }
            .refreshable { await refreshStorage() }
            .confirmationDialog(
                "Reset all settings to defaults?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    coord?.resetAllSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your recordings and locked clips will not be affected.")
            }
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        Section {
            Picker("Resolution", selection: Binding(
                get: { settings.resolution },
                set: { coord?.setResolution($0) }
            )) {
                ForEach(VideoResolution.allCases, id: \.self) { res in
                    Text(res.displayName).tag(res)
                }
            }

            Picker("Frame Rate", selection: Binding(
                get: { settings.frameRate },
                set: { coord?.setFrameRate($0) }
            )) {
                ForEach([24, 30, 60], id: \.self) { fps in
                    Text("\(fps) fps").tag(fps)
                }
            }

            Picker("Codec", selection: Binding(
                get: { settings.codec },
                set: { coord?.setCodec($0) }
            )) {
                Text("HEVC").tag(VideoCodec.hevc)
                Text("H.264").tag(VideoCodec.h264)
            }

            NavigationLink {
                bitrateDetail
            } label: {
                LabeledContent("Bitrate", value: bitrateLabel)
            }

            Picker("Loop Length", selection: Binding(
                get: { settings.segmentDuration },
                set: { coord?.setSegmentDuration($0) }
            )) {
                Text("30 min").tag(TimeInterval(30 * 60))
                Text("60 min").tag(TimeInterval(60 * 60))
                Text("90 min").tag(TimeInterval(90 * 60))
                Text("120 min").tag(TimeInterval(120 * 60))
                Text("3 hr").tag(TimeInterval(180 * 60))
            }

            Picker("Camera", selection: Binding(
                get: { settings.selectedCamera },
                set: { newValue in
                    Task { await coord?.setSelectedCamera(newValue) }
                }
            )) {
                Text("Back").tag(CameraPosition.backWide)
                Text("Front").tag(CameraPosition.front)
            }

            Toggle("Record Audio", isOn: Binding(
                get: { settings.audioEnabled },
                set: { coord?.setAudioEnabled($0) }
            ))
        } header: {
            Text("Capture")
        } footer: {
            Text("Changes apply at the start of the next recording session.")
        }
    }

    private var bitrateLabel: String {
        let baseline = settings.resolution.bitrate
        let adjusted = Double(baseline) * settings.bitrateMultiplier
        return String(format: "%.1f Mbps", adjusted / 1_000_000)
    }

    private var bitrateDetail: some View {
        Form {
            Section {
                HStack {
                    Text("0.5×")
                    Slider(value: Binding(
                        get: { settings.bitrateMultiplier },
                        set: { coord?.setBitrateMultiplier($0) }
                    ), in: 0.5...2.0, step: 0.1)
                    Text("2.0×")
                }
                LabeledContent("Current", value: String(format: "%.1f×", settings.bitrateMultiplier))
                LabeledContent("Effective Bitrate", value: bitrateLabel)
            } header: {
                Text("Bitrate Multiplier")
            } footer: {
                Text("Higher bitrates improve quality but increase storage and thermal load. The thermal policy may reduce this automatically at runtime.")
            }
        }
        .navigationTitle("Bitrate")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Detection

    private var detectionSection: some View {
        Section {
            Toggle("Emergency Vehicle Detection", isOn: Binding(
                get: { settings.policeDetectionEnabled },
                set: { coord?.setPoliceDetectionEnabled($0) }
            ))
            Toggle("Audible Alerts", isOn: Binding(
                get: { settings.detectionAudioEnabled },
                set: { coord?.setDetectionAudioEnabled($0) }
            ))
            .disabled(!settings.policeDetectionEnabled)

            Toggle("Show Diagnostics Overlay", isOn: Binding(
                get: { settings.showDetectionDiagnostics },
                set: { settings.showDetectionDiagnostics = $0 }
            ))
            .disabled(!settings.policeDetectionEnabled)
        } header: {
            Text("Detection")
        } footer: {
            Text("On-device detection of marked cruisers, unmarked fleet vehicles, and active emergency lights. All processing happens locally — no frames leave your device. Diagnostics overlay shows live pipeline health on the LIVE camera view — useful for verifying detection is running.")
        }
    }

    // MARK: - Incident

    private var incidentSection: some View {
        Section {
            Toggle("Auto-Lock on Impact", isOn: Binding(
                get: { settings.incidentDetectionEnabled },
                set: { newValue in Task { await coord?.setIncidentDetection(newValue) } }
            ))

            Picker("Sensitivity", selection: Binding(
                get: { settings.incidentSensitivity },
                set: { newValue in Task { await coord?.setIncidentSensitivity(newValue) } }
            )) {
                ForEach(IncidentSensitivity.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .disabled(!settings.incidentDetectionEnabled)

            Toggle("Hard-Brake Detection", isOn: Binding(
                get: { settings.hardBrakeDetectionEnabled },
                set: { coord?.setHardBrakeDetection($0) }
            ))

            Toggle("Parking Sentry", isOn: Binding(
                get: { settings.parkingSentryEnabled },
                set: { coord?.setParkingSentry($0) }
            ))
        } header: {
            Text("Incident Detection")
        } footer: {
            Text(settings.incidentSensitivity.description)
        }
    }

    // MARK: - Overlay

    private var overlaySection: some View {
        Section {
            Toggle("Speed", isOn: Binding(
                get: { settings.showSpeedOverlay },
                set: { coord?.setShowSpeedOverlay($0) }
            ))
            Toggle("GPS Coordinates", isOn: Binding(
                get: { settings.showGPSOverlay },
                set: { coord?.setShowGPSOverlay($0) }
            ))
            Toggle("G-Force Trace", isOn: Binding(
                get: { settings.showGForceOverlay },
                set: { coord?.setShowGForceOverlay($0) }
            ))
            Toggle("Watermark", isOn: Binding(
                get: { settings.watermarkEnabled },
                set: { coord?.setWatermarkEnabled($0) }
            ))
            if settings.watermarkEnabled {
                TextField("Watermark Text", text: Binding(
                    get: { settings.watermarkText },
                    set: { coord?.setWatermarkText($0) }
                ))
                .textInputAutocapitalization(.words)
            }
        } header: {
            Text("Clip Overlay")
        } footer: {
            Text("Selected overlays are burned into exported video files.")
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section {
            Picker("Storage Cap", selection: Binding(
                get: { settings.storageCap },
                set: { coord?.setStorageCap($0) }
            )) {
                Text("2 GB").tag(Int64(2) * 1_073_741_824)
                Text("5 GB").tag(Int64(5) * 1_073_741_824)
                Text("10 GB").tag(Int64(10) * 1_073_741_824)
                Text("25 GB").tag(Int64(25) * 1_073_741_824)
                Text("50 GB").tag(Int64(50) * 1_073_741_824)
                Text("100 GB").tag(Int64(100) * 1_073_741_824)
            }

            storageBarRow
                .listRowSeparator(.hidden)

            Toggle("Auto-Export to Photos", isOn: Binding(
                get: { settings.autoExportToPhotos },
                set: { newValue in Task { await coord?.setAutoExportToPhotos(newValue) } }
            ))
            Toggle("iCloud Backup", isOn: Binding(
                get: { settings.iCloudBackupEnabled },
                set: { coord?.setiCloudBackup($0) }
            ))
        } header: {
            Text("Storage")
        } footer: {
            Text("Loop clips are deleted oldest-first when the cap is reached. Locked clips are never deleted.")
        }
    }

    private var storageBarRow: some View {
        let capBytes = Double(settings.storageCap)
        let loopBytes = Double(storageUsedBytes - lockedBytes)
        let loopFraction = capBytes > 0 ? max(0, min(1, loopBytes / capBytes)) : 0
        let lockedFraction = capBytes > 0 ? max(0, min(1, Double(lockedBytes) / capBytes)) : 0

        return VStack(alignment: .leading, spacing: CCTheme.Space.sm) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CCTheme.accent)
                        .frame(width: max(0, geo.size.width * loopFraction))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CCTheme.red)
                        .frame(width: max(0, geo.size.width * lockedFraction))
                    Spacer(minLength: 0)
                }
                .frame(height: 6)
                .background(
                    RoundedRectangle(cornerRadius: 3).fill(Color(.tertiarySystemFill))
                )
            }
            .frame(height: 6)

            HStack(spacing: CCTheme.Space.md) {
                legend(color: CCTheme.accent, label: "Loop", bytes: storageUsedBytes - lockedBytes)
                legend(color: CCTheme.red, label: "Locked", bytes: lockedBytes)
                Spacer()
                legend(color: .secondary, label: "Free", bytes: deviceFreeBytes)
            }
        }
        .padding(.vertical, 4)
    }

    private func legend(color: Color, label: String, bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(formatBytes(bytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recording behavior

    private var recordingBehaviorSection: some View {
        Section {
            Toggle("Auto-Start on Launch", isOn: Binding(
                get: { settings.autoStartOnLaunch },
                set: { coord?.setAutoStartOnLaunch($0) }
            ))
            Toggle("Dim Display While Recording", isOn: Binding(
                get: { settings.dimDisplayWhileRecording },
                set: { coord?.setDimDisplayWhileRecording($0) }
            ))
            Toggle("Haptic Feedback", isOn: Binding(
                get: { settings.hapticsEnabled },
                set: { coord?.setHapticsEnabled($0) }
            ))
        } header: {
            Text("Recording Behavior")
        }
    }

    // MARK: - Thermal

    private var thermalSection: some View {
        Section {
            LabeledContent("Current Tier") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(container.thermalMonitor.currentTier.color)
                        .frame(width: 8, height: 8)
                    Text(container.thermalMonitor.currentTier.label.capitalized)
                        .font(.subheadline.weight(.medium))
                }
            }

            Toggle("Allow Thermal Throttling", isOn: Binding(
                get: { settings.allowThermalThrottling },
                set: { coord?.setAllowThermalThrottling($0) }
            ))
        } header: {
            Text("Thermal")
        } footer: {
            Text("When enabled, CarCam Pro reduces framerate and resolution under high device temperature to prevent shutdown.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
            NavigationLink("About CarCam Pro") {
                AboutView()
            }
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Text("Reset All Settings")
            }
        } header: {
            Text("About")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // MARK: - Storage refresh

    private func refreshStorage() async {
        let usage = await container.storageManager?.calculateTotalUsage() ?? 0
        let free = container.storageManager?.availableDeviceSpace() ?? 0
        storageUsedBytes = usage
        deviceFreeBytes = free

        if let modelContainer = container.modelContainer {
            let ctx = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<VideoClip>(
                predicate: #Predicate<VideoClip> { clip in clip.isProtected == true }
            )
            let locked = (try? ctx.fetch(descriptor)) ?? []
            lockedBytes = locked.reduce(0) { $0 + $1.fileSize }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: CCTheme.Space.md) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(CCTheme.accent)
                    Text("CarCam Pro")
                        .font(.title.weight(.bold))
                    Text("A native iOS dashcam engineered for thermal endurance.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, CCTheme.Space.lg)
                .listRowBackground(Color.clear)
            }

            Section("Learn More") {
                Link(destination: URL(string: "https://github.com/jwillz7667/CarCamPro")!) {
                    Label("Source & Documentation", systemImage: "doc.text.fill")
                }
                Link(destination: URL(string: "https://github.com/jwillz7667/CarCamPro/blob/main/SECURITY.md")!) {
                    Label("Security Policy", systemImage: "lock.shield.fill")
                }
                Link(destination: URL(string: "https://github.com/jwillz7667/CarCamPro/blob/main/LICENSE")!) {
                    Label("License", systemImage: "doc.plaintext.fill")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
