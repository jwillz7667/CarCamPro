import SwiftUI
import MapKit
import OSLog

/// MAP tab — live map with a floating ETA card, mini-feed, and the impact-guard
/// toggle panel. Uses `MapKit` in hybrid dark style to match the mockup's
/// low-saturation palette.
struct MapDashboardView: View {
    @Environment(DependencyContainer.self) private var container
    @Binding var activeTab: CCTab

    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    )

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
            .colorScheme(.dark)

            VStack(spacing: 0) {
                CCTopBar {
                    CCArmedIndicator(
                        armed: container.recordingEngine.state.isRecording,
                        storageFree: "48.2 GB"
                    )
                }
                .background(gradientTop)

                etaCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Spacer()

                bottomHUDRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var gradientTop: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.95), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - ETA card

    private var etaCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                CCLabel("ACTIVE ROUTE", size: 9, color: CCTheme.amber)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(distanceLabel)
                        .font(CCFont.sans(18, weight: .regular))
                        .foregroundStyle(CCTheme.ink)
                    Text("·")
                        .foregroundStyle(CCTheme.ink3)
                    Text(etaLabel)
                        .font(CCFont.sans(13))
                        .foregroundStyle(CCTheme.ink3)
                }
                .padding(.top, 2)
                CCLabel(routeLabel, size: 10, color: CCTheme.ink3)
                    .padding(.top, 2)
            }

            Rectangle().fill(CCTheme.rule).frame(width: 1, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                CCLabel("SPEED", size: 9, color: CCTheme.ink4)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(speedLabel)
                        .font(CCFont.mono(22, weight: .light))
                        .foregroundStyle(CCTheme.ink)
                    Text("MPH")
                        .font(CCFont.mono(10))
                        .foregroundStyle(CCTheme.ink4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.black.opacity(0.82))
        .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
    }

    private var distanceLabel: String {
        guard let s = container.recordingEngine.lastLocationSample else { return "—" }
        let miles = container.recordingEngine.currentSessionMiles
        return String(format: "%.1f mi", miles)
    }

    private var etaLabel: String {
        let duration = container.recordingEngine.currentDuration
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }

    private var routeLabel: String {
        if container.recordingEngine.state.isRecording {
            return "LIVE · Recording in progress"
        }
        return "Standby — tap REC to begin"
    }

    private var speedLabel: String {
        guard let mph = container.recordingEngine.lastLocationSample?.speedMPH else { return "0" }
        return String(Int(mph.rounded()))
    }

    // MARK: - Bottom row

    private var bottomHUDRow: some View {
        HStack(spacing: 10) {
            miniFeed
                .frame(width: 108, height: 72)

            impactGuardPanel
        }
    }

    private var miniFeed: some View {
        CCFeedPlaceholder(label: "CAM 01") {
            HStack(spacing: 4) {
                CCRecDot(size: 5)
                CCLabel("REC", size: 7, color: CCTheme.red)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
    }

    private var impactGuardPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CCLabel("IMPACT GUARD", size: 9, color: CCTheme.ink4)
                Spacer()
                CCLabel("● ARMED", size: 9, color: CCTheme.green)
            }
            Text("Auto-lock on impact > 1.5g")
                .font(CCFont.sans(13))
                .foregroundStyle(CCTheme.ink)
            HStack(spacing: 6) {
                guardChip(title: "LOCK CLIP", color: CCTheme.amber) {
                    Task { await container.recordingEngine.protectCurrentClip() }
                }
                guardChip(title: "MARK", color: CCTheme.ink3) {
                    // Mark-only (no file protection) — logged for later review.
                    AppLogger.ui.info("User marked current moment")
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.82))
        .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
    }

    private func guardChip(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CCFont.mono(9, weight: .medium))
                .kerning(1.4)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(Rectangle().stroke(CCTheme.ruleHi, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
