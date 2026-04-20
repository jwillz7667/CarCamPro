# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CarCam Pro (bundle: `Res.CarCam-Pro`) is a native iOS dashcam app that turns an iPhone into a dashboard camera. The core differentiator is aggressive thermal and battery management to sustain 2+ hours of continuous recording without thermal shutdown — the #1 complaint in competing apps.

## Build & Run

```bash
# Open project
open "CarCam Pro.xcodeproj"

# Build from CLI (requires Xcode 26+, iOS 26.0+ deployment target)
xcodebuild -scheme "CarCam Pro" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run tests
xcodebuild test -scheme "CarCam Pro" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

- **Swift version:** 5.0 (use Swift 6 concurrency patterns: async/await, actors, structured concurrency)
- **Min deployment:** iOS 26.0
- **Zero third-party dependencies** — all Apple frameworks

## Architecture

**Clean Architecture + MVVM** with protocol-driven dependency injection.

Planned directory structure:
```
CarCam Pro/
├── App/           → DashCamProApp, AppDelegate, DependencyContainer
├── Core/          → Services (Camera, Recording, Thermal, Incident, Storage, Location)
├── Features/      → Feature modules (Recording, Library, Settings, Onboarding, Paywall)
├── Shared/        → Extensions, Utilities, Constants
├── Resources/     → Assets, Localizable strings
└── Tests/         → Unit + UI tests
```

### Key Service Boundaries

- **CameraService** — AVCaptureSession management on a dedicated DispatchQueue (AVFoundation requirement)
- **RecordingEngine** — `@MainActor` state machine: idle → starting → recording → rotating → stopping → error
- **ThermalMonitor** — `actor` type, observes `ProcessInfo.thermalState`, triggers 4-tier quality policy
- **IncidentDetector** — `actor` type, Core Motion accelerometer at 60Hz, g-force threshold detection
- **StorageManager** — Loop recording with FIFO deletion, storage cap enforcement
- **LocationService** — GPS coordinates and speed per clip

All services conform to protocols (`CameraServiceProtocol`, etc.) for testability. Wired via `DependencyContainer` at launch.

### Concurrency Model

- Camera pipeline: dedicated `DispatchQueue` (required by AVFoundation)
- Core Motion: `OperationQueue`
- Everything else: `async/await` with `actor` isolation
- ViewModels: `@Observable` macro

## Critical Domain Knowledge

### Thermal Management (4-Tier Policy)

This is the app's most important feature. Every decision should consider thermal impact.

| Tier | Trigger | Actions |
|------|---------|---------|
| Nominal | Default | Full user-configured quality |
| Fair | `.fair` | 24fps, -20% bitrate, dim display |
| Serious | `.serious` | Force 720p/24fps/1.5Mbps, min display, Core Motion → 10Hz |
| Critical | `.critical` | 720p/15fps/800Kbps, display off, pause incident detection |

Recovery requires 60-second delay before stepping back up (prevents oscillation).

### Background Recording

Uses multi-signal approach to avoid iOS background kill:
1. `AVAudioSession` with `.playAndRecord` (keeps capture session alive)
2. `CLLocationManager` with `allowsBackgroundLocationUpdates = true`
3. `BGProcessingTask` for storage cleanup when suspended
4. Live Activity in Dynamic Island

Info.plist background modes: `audio`, `location`, `processing`.

### Incident Detection

- Total g-force: `sqrt(x² + y² + z²) - 1.0`
- Thresholds: Low=6g+, Medium=3g+, High=1.5g+
- 10-second debounce between events
- Protects current segment + 30s before/after (60s for Premium)

### Subscription Tiers (StoreKit 2)

| | Free | Pro ($4.99/mo) | Premium ($9.99/mo) |
|--|------|---------------|-------------------|
| Resolution | 720p | 1080p | 4K |
| Storage | 2GB | 10GB | Unlimited |
| Background | No | Yes | Yes |
| Incidents | No | Yes | Yes (60s buffer) |

## Data Models (SwiftData)

- **RecordingSession** — groups clips, tracks duration and interruptions
- **VideoClip** — file path, encoding params, GPS data, incident metadata, protection status
- **Settings** — stored via `@AppStorage` (resolution, fps, codec, sensitivity, etc.)

File naming: `clip_{session-short-id}_{sequence}_{timestamp}.mp4`
Storage layout: `Documents/Recordings/{YYYY-MM-DD}/{session_id}/`

## UI Design

- **iOS 26 Liquid Glass**: all UI uses `.glassEffect()` floating over live camera feed
- **Dark-first**: #0A0A0A background, no opaque panels
- **One-thumb operation**: Record button bottom-center, 72pt glass circle
- **Interactive feedback**: `.interactive()` modifier for press animations, `.sensoryFeedback()` for haptics
- Camera preview via `UIViewRepresentable`

## Design Docs

Detailed specifications live in `docs/`:
- `01-PRD` — Product requirements, user personas, feature matrix
- `02-Technical-Architecture` — Framework choices, concurrency model
- `03-System-Design-Data-Models` — SwiftData schemas, file system layout
- `04-Thermal-Battery-Optimization` — Thermal tier policies, battery strategies
- `05-UI-UX-Specifications` — Screen-by-screen design specs
- `06-Sprint-Plan-Roadmap` — 6-phase implementation plan
- `08-Claude-Code-Implementation-Tickets` — Implementation tickets
- `11-iOS26-Liquid-Glass-UI-Design-System` — Liquid Glass component specs
- `12-Updated-Tickets-Pricing-and-UI` — Revised tickets with iOS 26 + pricing updates

Consult these docs before implementing any feature — they contain exact specifications.
