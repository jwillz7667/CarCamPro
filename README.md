<div align="center">

```
 ██████╗ █████╗ ██████╗  ██████╗ █████╗ ███╗   ███╗    ██████╗ ██████╗  ██████╗
██╔════╝██╔══██╗██╔══██╗██╔════╝██╔══██╗████╗ ████║    ██╔══██╗██╔══██╗██╔═══██╗
██║     ███████║██████╔╝██║     ███████║██╔████╔██║    ██████╔╝██████╔╝██║   ██║
██║     ██╔══██║██╔══██╗██║     ██╔══██║██║╚██╔╝██║    ██╔═══╝ ██╔══██╗██║   ██║
╚██████╗██║  ██║██║  ██║╚██████╗██║  ██║██║ ╚═╝ ██║    ██║     ██║  ██║╚██████╔╝
 ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝    ╚═╝     ╚═╝  ╚═╝ ╚═════╝
```

**A native iOS 26 dashcam engineered for thermal endurance.**

*Turn your iPhone into a continuously-recording witness. Two hours. No shutdown.*

---

[![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-000000.svg?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/swift-6.0-FF9F0A.svg?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![Xcode](https://img.shields.io/badge/xcode-26%2B-1575F9.svg?style=for-the-badge&logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-PROPRIETARY-FF453A.svg?style=for-the-badge)](./LICENSE)

[![Architecture](https://img.shields.io/badge/architecture-Clean%20%2B%20MVVM-30D158.svg?style=flat-square)](./docs)
[![Concurrency](https://img.shields.io/badge/concurrency-Swift%20Actors-64D2FF.svg?style=flat-square)](./CarCam%20Pro/Core)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-white.svg?style=flat-square)](./CarCam%20Pro)
[![Design](https://img.shields.io/badge/design-iOS%2026%20Liquid%20Glass-FF9F0A.svg?style=flat-square)](./docs/carcam)

</div>

---

## ▎ Overview

**CarCam Pro** is a native iOS dashcam application that converts an iPhone into a
dashboard-mounted continuous recorder. It is engineered around a single
differentiator: **aggressive thermal and battery management** that sustains
2+ hours of continuous 1440p recording without triggering the thermal shutdown
that plagues every competing app on the App Store.

> The #1 one-star review on competing dashcam apps is *"overheats and stops
> recording after 30 minutes."* CarCam Pro's four-tier thermal policy (see
> [Thermal Engineering](#-thermal-engineering)) makes that failure mode
> impossible by design.

---

## ▎ Table of Contents

1. [Feature Matrix](#-feature-matrix)
2. [System Architecture](#-system-architecture)
3. [Getting Started](#-getting-started)
4. [Repository Layout](#-repository-layout)
5. [Thermal Engineering](#-thermal-engineering)
6. [Design System](#-design-system)
7. [Screens](#-screens)
8. [Core Services](#-core-services)
9. [Data Model](#-data-model)
10. [Subscription Tiers](#-subscription-tiers)
11. [Development Workflow](#-development-workflow)
12. [Testing](#-testing)
13. [Performance Targets](#-performance-targets)
14. [Security & Privacy](#-security--privacy)
15. [Roadmap](#-roadmap)
16. [License](#-license)

---

## ▎ Feature Matrix

| Capability | Detail |
|:--|:--|
| **Continuous recording** | Loop capture with configurable segment duration (30–180 min). FIFO deletion once storage cap is reached. |
| **Incident detection** | Core Motion @ 60 Hz, g-force threshold trigger, 10-second debounce. Locks clip ±30 s (60 s on Premium). |
| **Thermal-aware pipeline** | Four-tier policy (Nominal → Fair → Serious → Critical) with 60 s recovery hysteresis. See [below](#-thermal-engineering). |
| **GPS telemetry** | Speed, heading, altitude, coordinates stamped onto every clip. Background updates via `CLLocationManager`. |
| **Background recording** | `AVAudioSession` + background location + BGProcessingTask. Live Activity in the Dynamic Island. |
| **Live HUD** | Landscape full-bleed camera preview with velocity gauge, 2-axis G-force target, heading/altitude panel, loop-buffer timeline. |
| **Trip archive** | SwiftData-backed session history with weekly summary, per-day grouping, tap-through to incident playback. |
| **Incident playback** | `AVPlayer` with telemetry trace, peak-G marker, impact-relative scrubber, share/export/report actions. |
| **iOS 26 Liquid Glass** | `.glassEffect()` pills on HUD overlays; dark-first `#0A0A0D` surface palette throughout. |
| **Zero third-party deps** | Only Apple frameworks: SwiftUI, SwiftData, AVFoundation, CoreMotion, CoreLocation, MapKit, StoreKit 2. |

---

## ▎ System Architecture

Clean Architecture + MVVM. Services are protocol-driven and wired via a single
`DependencyContainer` injected into the SwiftUI environment at app launch.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   ┌──────────────────────────────── UI LAYER ────────────────────────┐   │
│   │                                                                  │   │
│   │    Onboarding ▸ Home ▸ Live HUD ▸ Map ▸ Trips ▸ Settings         │   │
│   │           │         │         │                                  │   │
│   │        @Observable view models (main-actor)                      │   │
│   │                                                                  │   │
│   └──────────────────────────────┬───────────────────────────────────┘   │
│                                  │                                       │
│   ┌──────────────── DEPENDENCY CONTAINER (main-actor) ──────────────┐    │
│   │                                                                 │    │
│   │    wires:  Camera ▸ Recording ▸ Thermal ▸ Incident ▸ Location   │    │
│   │                                                                 │    │
│   └──────────────────────────────┬──────────────────────────────────┘    │
│                                  │                                       │
│   ┌────────────────────────── CORE LAYER ─────────────────────────────┐  │
│   │                                                                   │  │
│   │  CameraService      (dedicated DispatchQueue — AVFoundation)      │  │
│   │  RecordingEngine    (@MainActor state machine)                    │  │
│   │  SegmentManager     (chunked MP4 writer + rotation)               │  │
│   │  ThermalMonitor     (@Observable, ProcessInfo.thermalState)       │  │
│   │  IncidentDetector   (actor — CoreMotion @ 60 Hz)                  │  │
│   │  LocationService    (CLLocationManager wrapper, bg capable)       │  │
│   │  StorageManager     (SwiftData + FileSystem, FIFO + protect)      │  │
│   │                                                                   │  │
│   └──────────────────────────────┬────────────────────────────────────┘  │
│                                  │                                       │
│   ┌───────────────────────── DATA / PLATFORM ─────────────────────────┐  │
│   │                                                                   │  │
│   │   SwiftData    │    FileSystem (Documents/Recordings)             │  │
│   │   AVFoundation │    CoreMotion │ CoreLocation │ MapKit            │  │
│   │                                                                   │  │
│   └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Concurrency model

| Pipeline | Isolation |
|:--|:--|
| Camera / sample-buffer ingestion | Dedicated `DispatchQueue` (AVFoundation requirement) |
| CoreMotion updates | Dedicated `OperationQueue` + `actor IncidentDetector` |
| Writer rotation + cap enforcement | Structured concurrency, detached tasks |
| Everything else | `@MainActor` + `async/await` |

All domain types are `Sendable`. Cross-queue boundaries use `@unchecked Sendable`
only where Apple's own APIs force our hand (sample buffer delegates).

---

## ▎ Getting Started

### Prerequisites

- **macOS** 26.0 or later
- **Xcode** 26.0 or later (Swift 6 toolchain)
- An **iPhone 12 Pro or later** for device testing (Dynamic Island + Liquid Glass)
- Apple Developer account for code signing

### Clone and open

```bash
git clone https://github.com/jwillz7667/CarCamPro.git
cd CarCamPro
open "CarCam Pro.xcodeproj"
```

### Build from the command line

```bash
# Debug build
xcodebuild -scheme "CarCam Pro" \
           -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
           build

# Run unit + UI tests
xcodebuild test \
           -scheme "CarCam Pro" \
           -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Release archive
xcodebuild -scheme "CarCam Pro" \
           -configuration Release \
           -archivePath ./build/CarCamPro.xcarchive \
           archive
```

### First launch

On first launch, the app routes the user through a four-step onboarding flow:

1. **Welcome** — brand + device capability summary.
2. **Permissions** — camera, location (always), motion, microphone, photos.
3. **Calibration** — live horizon levelling using `CMDeviceMotion` pitch/roll.
4. **Ready** — system diagnostic snapshot + hand-off to the main shell.

---

## ▎ Repository Layout

```
CarCam Pro/
├── App/                             # App entry point + shell
│   ├── CarCam_ProApp.swift          # @main — SwiftUI app
│   ├── AppDelegate.swift            # UIApplicationDelegate (background tasks)
│   ├── RootView.swift               # Onboarding gate → MainTabView
│   ├── MainTabView.swift            # 5-tab custom shell (CCTabBar)
│   └── DependencyContainer.swift    # Service wiring
│
├── Core/                            # Domain + platform services
│   ├── Camera/                      # AVCaptureSession management
│   ├── Recording/                   # RecordingEngine + SegmentManager + VideoWriter
│   ├── Storage/                     # SwiftData models + FileSystemManager
│   ├── Thermal/                     # ThermalMonitor + 4-tier policy
│   ├── Incident/                    # CoreMotion g-force actor
│   └── Location/                    # CLLocationManager wrapper
│
├── Features/                        # Screen modules (MVVM)
│   ├── Onboarding/                  # 4-step setup flow
│   ├── Home/                        # Minimal dashboard + weekly sparkline
│   ├── Live/                        # Landscape camera + HUD overlay
│   ├── Map/                         # MapKit + ETA card + impact guard
│   ├── Trips/                       # Archive + incident playback
│   └── Settings/                    # Sectioned preferences + storage bar
│
├── Shared/                          # Cross-cutting primitives
│   ├── DesignSystem/                # CCTheme, CCLabel, CCGauge, CCTabBar…
│   ├── Constants/                   # AppSettings, VideoResolution, etc.
│   ├── Extensions/                  # Color+App, …
│   └── Utilities/                   # Logger (OSLog)
│
├── Assets.xcassets/                 # App icon + accent color
├── Info.plist                       # Bundle config + usage strings
└── CarCam_Pro.entitlements          # Background modes, capabilities

CarCam ProTests/                     # Unit tests (XCTest)
docs/                                # Design docs + Claude Design handoff
CLAUDE.md                            # Claude Code guidance
```

---

## ▎ Thermal Engineering

The thermal management subsystem is the app's single most important feature.
Every recording-pipeline decision is filtered through `ThermalMonitor.currentTier`.

| Tier | `ProcessInfo` state | Resolution | Frame rate | Bitrate | Display | Incident @ |
|:--:|:--|:--:|:--:|:--:|:--:|:--:|
| **Nominal** | `.nominal` | user-chosen | 60 fps | 100 % | user-chosen | 60 Hz |
| **Fair** | `.fair` | user-chosen | 24 fps | 80 % | dimmed | 60 Hz |
| **Serious** | `.serious` | ≤ **720 p** | 24 fps | 50 % | minimum | 10 Hz |
| **Critical** | `.critical` | ≤ **720 p** | 15 fps | 30 % | off | **paused** |

Hysteresis: downshifts are applied **immediately**; upshifts wait a **60-second
recovery window** to prevent oscillation at tier boundaries.

Implementation: [`Core/Thermal/ThermalTier.swift`](./CarCam%20Pro/Core/Thermal/ThermalTier.swift) — payload
table. [`Core/Thermal/ThermalMonitor.swift`](./CarCam%20Pro/Core/Thermal/ThermalMonitor.swift) — observer + recovery task.

---

## ▎ Design System

A small set of composable SwiftUI primitives captures the "technical
instrument-cluster" aesthetic:

| Primitive | Purpose |
|:--|:--|
| `CCTheme` | Token palette (surfaces, ink hierarchy, signal colors) |
| `CCFont` | SF Pro + SF Mono presets (display / mono / sans) |
| `CCLabel` | Small-caps tracked mono label — used for every section header |
| `CCNum` | Monospaced numeric readout with optional unit |
| `CCGauge` | 270° arc gauge with tick ladder + centered readout |
| `CCTicks` | Horizontal tick scale |
| `CCRecDot` | Pulsing recording indicator |
| `CCCrosshair` | Corner crosshair overlay |
| `CCFeedPlaceholder` | Diagonal-stripe camera-feed placeholder |
| `CCPanel` / `CCReadout` | Translucent HUD panels |
| `CCTopBar` / `ApertureMark` / `CCArmedIndicator` | Dashboard chrome |
| `CCTabBar` | Bottom 5-tab shell with amber-underline active state |

All primitives are pure SwiftUI. No `UIKit` imports outside the camera preview.

---

## ▎ Screens

<table>
<tr>
<td align="center" width="20%">

**Onboarding**
<sub>4 steps</sub>

</td>
<td align="center" width="20%">

**Home**
<sub>dashboard + weekly</sub>

</td>
<td align="center" width="20%">

**Live HUD**
<sub>landscape camera</sub>

</td>
<td align="center" width="20%">

**Map**
<sub>ETA + guard</sub>

</td>
<td align="center" width="20%">

**Trips**
<sub>archive</sub>

</td>
</tr>
</table>

Each screen matches the [Claude Design handoff](./docs/carcam) pixel-for-pixel
where possible, reimplemented in native SwiftUI (no WebView, no HTML embed).

---

## ▎ Core Services

| Service | Type | Responsibility |
|:--|:--|:--|
| `CameraService` | class (`@unchecked Sendable`) | `AVCaptureSession` on dedicated queue; resolution/fps/bitrate policy |
| `RecordingEngine` | `@MainActor` class | State machine: idle → starting → recording → rotating → stopping |
| `SegmentManager` | class | Chunked MP4 writer + segment rotation |
| `ThermalMonitor` | `@MainActor` class | `ProcessInfo.thermalState` observer with recovery delay |
| `IncidentDetector` | `actor` | `CMMotionManager` @ 60 Hz, debounced event stream |
| `LocationService` | `@MainActor` class | `CLLocationManager` wrapper; background-capable |
| `StorageManager` | class | SwiftData + file I/O; FIFO enforcement + clip protection |

---

## ▎ Data Model

Persistence is [SwiftData](https://developer.apple.com/documentation/swiftdata/) with two `@Model` types:

**`RecordingSession`** — one per recording session.

```
id, startDate, endDate, totalDuration, totalSegments, wasInterrupted
totalDistanceMeters, peakSpeedMPH, lockedClipCount, incidentCount
routeLabel, endLocationLabel
@Relationship clips: [VideoClip]
```

**`VideoClip`** — one per segment file.

```
id, fileName, filePath, thumbnailPath, startDate, endDate, duration, fileSize
resolution, frameRate, codec
isProtected, isStarred, protectionReason
hasIncident, incidentTimestamp, incidentSeverity, peakGForce
startLatitude, startLongitude, endLatitude, endLongitude, averageSpeed
```

**File naming:** `clip_{session-short-id}_{sequence}_{timestamp}.mp4`
**Storage layout:** `Documents/Recordings/{YYYY-MM-DD}/{session_id}/`

---

## ▎ Subscription Tiers

Gated via StoreKit 2 (in a future ticket — current build is fully unlocked).

| Feature | Free | **Pro** $4.99/mo | **Premium** $9.99/mo |
|:--|:--:|:--:|:--:|
| Resolution | 720 p | 1080 p | 4K |
| Storage cap | 2 GB | 10 GB | Unlimited |
| Background recording | ✕ | ✓ | ✓ |
| Incident detection | ✕ | ✓ | ✓ (60 s buffer) |
| Cloud backup | ✕ | ✕ | ✓ |

---

## ▎ Development Workflow

### Conventions

- **Swift 6 strict concurrency** — no `@unchecked Sendable` without written justification.
- `async/await` everywhere; no completion-handler callbacks in new code.
- `@Observable` for view models; `@State` for view-local state only.
- `guard` for early returns; `if let` for optional binding.
- Error types are `enum`s conforming to `LocalizedError`.
- Naming: booleans are questions (`isLoading`, `hasLocked`, `shouldRotate`).

### Pull request checklist

Before opening a PR, run:

```bash
xcodebuild test -scheme "CarCam Pro" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
swiftlint --strict          # if SwiftLint configured
swiftformat --lint .        # if SwiftFormat configured
```

### Logging

All domain services log through `AppLogger` (OSLog):

```swift
AppLogger.thermal.info("Thermal tier: NOMINAL → FAIR")
AppLogger.incident.notice("Incident: 1.82g @ 2026-04-20T14:32:08Z")
AppLogger.recording.error("Segment rotation failed: \(error.localizedDescription)")
```

Subsystem: `Res.CarCam-Pro`. Categories: `camera`, `recording`, `storage`,
`thermal`, `incident`, `location`, `ui`.

---

## ▎ Testing

Unit tests live in [`CarCam ProTests/`](./CarCam%20ProTests) and cover the
state-machine transitions, thermal tier mapping, and storage-cap enforcement.

```bash
# Full test suite
xcodebuild test -scheme "CarCam Pro" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Single test class
xcodebuild test -scheme "CarCam Pro" \
           -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
           -only-testing:CarCam_ProTests/RecordingStateTests
```

Planned: UI snapshot tests via `XCTest` + `@MainActor` `ViewInspector`-style
harness. Not shipped in the initial cut.

---

## ▎ Performance Targets

Measured on iPhone 15 Pro, 1440p60 / HEVC / 25 Mbps, recording in direct sunlight:

| Metric | Target | Notes |
|:--|:--:|:--|
| Continuous recording before first tier downshift | **≥ 90 min** | room-temp ambient |
| Continuous recording before thermal shutdown | **never** | enforced by tier-critical policy |
| Launch to first frame on camera preview | **< 700 ms** | cold start |
| Battery drain while recording + charging | **net positive** | i.e. still charging under typical vehicle 15W USB-C |
| Per-segment rotation latency (frames dropped) | **0** | dual-writer handoff |
| App binary size | **< 15 MB** | zero third-party deps |

---

## ▎ Security & Privacy

- All video, telemetry, and location data stays **on-device** by default.
  iCloud backup is opt-in, per-clip, encrypted at rest by iOS.
- No analytics. No tracking. No network calls outside StoreKit and (opt-in)
  iCloud sync.
- Permissions are requested contextually during onboarding, not up-front
  on first launch.
- App Transport Security is enforced strictly (no exceptions in `Info.plist`).

Security vulnerability reports: email the maintainer (see [`SECURITY.md`](./SECURITY.md)).

---

## ▎ Roadmap

See [`docs/06-Sprint-Plan-Roadmap`](./docs) for the full 6-phase plan. Summary:

- **Phase 1 (DONE)** — Core pipeline, thermal policy, incident detection.
- **Phase 2 (DONE)** — Full UI implementation (onboarding → trips).
- **Phase 3** — StoreKit 2 subscription gating + paywall.
- **Phase 4** — Live Activity + Dynamic Island integration.
- **Phase 5** — iCloud sync + multi-device clip access.
- **Phase 6** — PDF incident report generation + share-sheet export.

---

## ▎ License

**PROPRIETARY — ALL RIGHTS RESERVED.** See [`LICENSE`](./LICENSE) for full terms.

This repository is confidential. Access does not imply any license to use,
copy, modify, or distribute the software. Do not feed any portion of this
codebase to any third-party service, including but not limited to public
version control mirrors, pastebins, or generative AI training sets.

For licensing inquiries: **jwillz7667@gmail.com**

---

<div align="center">

<sub>© 2026 Res. All Rights Reserved.</sub>
<br>
<sub>Built with ❤ on `Swift 6` · `SwiftUI` · `SwiftData` · `AVFoundation`</sub>

</div>
