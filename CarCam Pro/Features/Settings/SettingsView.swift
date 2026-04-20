import SwiftUI
import SwiftData

/// SETTINGS tab — preference editor grouped by section (CAPTURE, INCIDENT,
/// OVERLAY, STORAGE). Each row is either a value row (navigate to detail) or
/// a toggle row. Storage usage is calculated live from `StorageManager`.
struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var settings = AppSettings.shared
    @State private var storageUsedBytes: Int64 = 0
    @State private var deviceFreeBytes: Int64 = 0
    @State private var lockedBytes: Int64 = 0

    var body: some View {
        ZStack {
            CCTheme.void.ignoresSafeArea()

            VStack(spacing: 0) {
                CCTopBar()

                header
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 24) {
                        captureSection
                        incidentSection
                        overlaySection
                        storageSection
                        storageBar
                        thermalSection
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, 60)
                }
            }
        }
        .task { await refreshStorage() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            CCLabel("SYSTEM / PREFERENCES", size: 9, color: CCTheme.ink4)
            Text("Settings")
                .font(CCFont.display(32, weight: .light))
                .kerning(-0.6)
                .foregroundStyle(CCTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private var captureSection: some View {
        SettingsSection(title: "CAPTURE", code: "§01") {
            SettingsValueRow(
                label: "Resolution",
                value: "\(settings.resolution.displayName) · \(settings.frameRate)fps"
            ) {
                settings.resolution = nextResolution(after: settings.resolution)
            }
            SettingsValueRow(label: "Codec", value: settings.codec.displayName) {
                settings.codec = settings.codec == .hevc ? .h264 : .hevc
            }
            SettingsValueRow(
                label: "Loop length",
                value: "\(Int(settings.segmentDuration / 60)) min"
            ) {
                settings.segmentDuration = nextSegmentDuration(after: settings.segmentDuration)
            }
            SettingsValueRow(
                label: "Bitrate",
                value: "\(settings.resolution.bitrate / 1_000_000) Mbps",
                last: true,
                action: {}
            )
        }
    }

    private var incidentSection: some View {
        SettingsSection(title: "INCIDENT DETECTION", code: "§02") {
            SettingsToggleRow(label: "Auto-lock on impact",
                              isOn: Binding(get: { settings.incidentDetectionEnabled },
                                            set: { settings.incidentDetectionEnabled = $0 }))
            SettingsValueRow(
                label: "Impact threshold",
                value: thresholdLabel(for: settings.incidentSensitivity)
            ) {
                settings.incidentSensitivity = nextSensitivity(after: settings.incidentSensitivity)
            }
            SettingsToggleRow(label: "Parking sentry",
                              isOn: Binding(get: { settings.autoStartOnLaunch },
                                            set: { settings.autoStartOnLaunch = $0 }))
            SettingsToggleRow(label: "Hard-brake detection",
                              isOn: Binding(get: { settings.allowThermalThrottling },
                                            set: { settings.allowThermalThrottling = $0 }),
                              last: true)
        }
    }

    private var overlaySection: some View {
        SettingsSection(title: "OVERLAY", code: "§03") {
            SettingsToggleRow(label: "Show speed on clip",
                              isOn: .constant(true))
            SettingsToggleRow(label: "Show GPS coordinates",
                              isOn: .constant(true))
            SettingsToggleRow(label: "Show G-force trace",
                              isOn: .constant(false))
            SettingsValueRow(label: "Watermark", value: "Off", last: true) {}
        }
    }

    private var storageSection: some View {
        SettingsSection(title: "STORAGE", code: "§04") {
            SettingsValueRow(
                label: "Used",
                value: "\(formatGB(storageUsedBytes)) / \(formatGB(settings.storageCap))"
            ) {}
            SettingsToggleRow(label: "Auto-export to Photos", isOn: .constant(true))
            SettingsToggleRow(label: "iCloud backup", isOn: .constant(false), last: true)
        }
    }

    private var storageBar: some View {
        let capBytes = Double(settings.storageCap)
        let unprotectedBytes = Double(storageUsedBytes - lockedBytes)
        let loopFraction = capBytes > 0 ? max(0, min(1, unprotectedBytes / capBytes)) : 0
        let lockedFraction = capBytes > 0 ? max(0, min(1, Double(lockedBytes) / capBytes)) : 0

        return VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Rectangle().fill(CCTheme.panel)
                    .frame(height: 4)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(CCTheme.amber)
                            .frame(width: geo.size.width * loopFraction)
                        Rectangle()
                            .fill(CCTheme.red)
                            .frame(width: geo.size.width * lockedFraction)
                    }
                }
                .frame(height: 4)
            }

            HStack {
                legendChip(color: CCTheme.amber, label: "LOOP \(formatGB(storageUsedBytes - lockedBytes))")
                Spacer()
                legendChip(color: CCTheme.red, label: "LOCKED \(formatGB(lockedBytes))")
                Spacer()
                legendChip(color: CCTheme.ink4,
                           label: "FREE \(formatGB(deviceFreeBytes))")
            }
        }
        .padding(.horizontal, 20)
    }

    private var thermalSection: some View {
        SettingsSection(title: "THERMAL", code: "§05") {
            SettingsValueRow(
                label: "Current tier",
                value: container.thermalMonitor.currentTier.label
            ) {}
            SettingsToggleRow(label: "Allow thermal throttling",
                              isOn: Binding(get: { settings.allowThermalThrottling },
                                            set: { settings.allowThermalThrottling = $0 }),
                              last: true)
        }
    }

    // MARK: - Helpers

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(CCFont.mono(9))
                .foregroundStyle(color)
        }
    }

    private func nextResolution(after r: VideoResolution) -> VideoResolution {
        let all = VideoResolution.allCases
        let idx = all.firstIndex(of: r) ?? 0
        return all[(idx + 1) % all.count]
    }

    private func nextSegmentDuration(after d: TimeInterval) -> TimeInterval {
        let options: [TimeInterval] = [30, 60, 90, 120, 180].map { $0 * 60 }
        let idx = options.firstIndex(of: d) ?? 0
        return options[(idx + 1) % options.count]
    }

    private func nextSensitivity(after s: IncidentSensitivity) -> IncidentSensitivity {
        switch s {
        case .low: return .medium
        case .medium: return .high
        case .high: return .low
        }
    }

    private func thresholdLabel(for s: IncidentSensitivity) -> String {
        switch s {
        case .low:    return "2.5 g"
        case .medium: return "1.5 g"
        case .high:   return "1.0 g"
        }
    }

    private func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        return String(format: "%.1f GB", gb)
    }

    private func refreshStorage() async {
        let usage = await container.storageManager?.calculateTotalUsage() ?? 0
        let free = container.storageManager?.availableDeviceSpace() ?? 0
        storageUsedBytes = usage
        deviceFreeBytes = free

        if let modelContainer = container.modelContainer {
            let ctx = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<VideoClip>(
                predicate: #Predicate<VideoClip> { clip in
                    clip.isProtected == true
                }
            )
            let locked = (try? ctx.fetch(descriptor)) ?? []
            lockedBytes = locked.reduce(0) { $0 + $1.fileSize }
        }
    }
}

// MARK: - Section primitives

struct SettingsSection<Content: View>: View {
    let title: String
    let code: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CCLabel(title, size: 9, color: CCTheme.ink3)
                Spacer()
                CCLabel(code, size: 9, color: CCTheme.ink4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                Rectangle().fill(CCTheme.rule).frame(height: 1)
                content()
                Rectangle().fill(CCTheme.rule).frame(height: 1)
            }
            .background(CCTheme.bg)
        }
    }
}

struct SettingsValueRow: View {
    let label: String
    let value: String
    var last: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(CCFont.sans(14))
                    .foregroundStyle(CCTheme.ink)
                Spacer()
                Text(value)
                    .font(CCFont.mono(12))
                    .foregroundStyle(CCTheme.amber)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(CCTheme.ink4)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(CCTheme.rule).frame(height: 1) }
            }
            .background(CCTheme.bg)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var last: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(CCFont.sans(14))
                .foregroundStyle(CCTheme.ink)
            Spacer()
            SquareToggle(isOn: $isOn)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(CCTheme.rule).frame(height: 1) }
        }
        .background(CCTheme.bg)
    }
}

/// Square-edged toggle matching the "technical" aesthetic of the mockups.
private struct SquareToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? CCTheme.amber : CCTheme.rule)
                    .frame(width: 36, height: 20)
                Rectangle()
                    .fill(isOn ? CCTheme.void : CCTheme.ink3)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
