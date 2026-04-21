import SwiftUI
import MapKit

/// MAP tab — a clean MapKit map with a single floating Liquid Glass ETA card
/// and a small toolbar of glass icon buttons. No mock route lines, no "impact
/// guard" panel cluttering the bottom; the user can start/stop recording
/// from here via a glass pill.
struct MapDashboardView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .automatic
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.gasStation, .parking])))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .ignoresSafeArea(edges: .bottom)

                VStack {
                    Spacer()

                    HStack(spacing: CCTheme.Space.md) {
                        speedCard
                        Spacer()
                        recordPill
                    }
                    .padding(.horizontal, CCTheme.Space.lg)
                    .padding(.bottom, CCTheme.Space.xl)
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Cards

    private var speedCard: some View {
        GlassStatusPill {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.subheadline)
                    .foregroundStyle(CCTheme.accent)
                Text(speedLabel)
                    .font(CCFont.mono(22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("mph")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recordPill: some View {
        GlassPillButton(
            style: isRecording ? .destructive : .prominent,
            action: toggleRecording
        ) {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "stop.circle.fill" : "record.circle.fill")
                    .font(.title3)
                Text(isRecording ? "Stop" : "Record")
            }
        }
    }

    // MARK: - Helpers

    private var isRecording: Bool {
        container.recordingEngine.state.isRecording
    }

    private var speedLabel: String {
        guard let mph = container.locationService.lastSample?.speedMPH, mph >= 1 else { return "0" }
        return String(Int(mph.rounded()))
    }

    private func toggleRecording() {
        Task {
            if isRecording {
                try? await container.recordingEngine.stopRecording()
            } else {
                try? await container.recordingEngine.startRecording()
            }
        }
    }
}
