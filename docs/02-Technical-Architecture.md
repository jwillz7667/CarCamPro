# Technical Architecture Document
## DashCam Pro — iOS Application

**Version:** 1.0
**Date:** April 12, 2026

---

## 1. Architecture Overview

DashCam Pro follows a **Clean Architecture** pattern with **MVVM** (Model-View-ViewModel) for the UI layer. The app is built entirely in **Swift** using **SwiftUI** for the interface and leverages Apple's native frameworks for all heavy lifting — no third-party dependencies for core functionality.

### 1.1 Architecture Diagram (Conceptual)

```
┌─────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ SwiftUI  │  │ ViewModels│  │  Navigation/      │  │
│  │ Views    │◄─┤ (@Observable)│ Coordinator     │  │
│  └──────────┘  └─────┬────┘  └───────────────────┘  │
│                      │                               │
├──────────────────────┼───────────────────────────────┤
│                 DOMAIN LAYER                         │
│  ┌───────────┐  ┌────┴─────┐  ┌──────────────────┐  │
│  │ Use Cases │  │ Entities │  │ Repository       │  │
│  │ /Interactors│ │ (Models) │  │ Protocols        │  │
│  └─────┬─────┘  └──────────┘  └────────┬─────────┘  │
│        │                                │            │
├────────┼────────────────────────────────┼────────────┤
│                  DATA / INFRA LAYER                  │
│  ┌─────┴──────┐  ┌─────────┐  ┌────────┴─────────┐  │
│  │ Camera     │  │ Storage  │  │ Motion/Location  │  │
│  │ Service    │  │ Manager  │  │ Services         │  │
│  └────────────┘  └─────────┘  └──────────────────┘  │
│  ┌────────────┐  ┌─────────┐  ┌──────────────────┐  │
│  │ Thermal    │  │ File    │  │ StoreKit         │  │
│  │ Monitor    │  │ Manager │  │ Manager          │  │
│  └────────────┘  └─────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 2. Project Structure

```
DashCamPro/
├── App/
│   ├── DashCamProApp.swift              # @main entry point
│   ├── AppDelegate.swift                # UIKit lifecycle hooks for background
│   └── DependencyContainer.swift        # DI container
│
├── Core/
│   ├── Camera/
│   │   ├── CameraService.swift          # AVCaptureSession management
│   │   ├── CameraConfiguration.swift    # Resolution, FPS, codec settings
│   │   └── CameraPreviewView.swift      # UIViewRepresentable for live preview
│   │
│   ├── Recording/
│   │   ├── RecordingEngine.swift         # Orchestrates recording lifecycle
│   │   ├── SegmentManager.swift          # Handles loop segments (start/stop/rotate)
│   │   ├── RecordingState.swift          # State machine for recording states
│   │   └── BackgroundRecordingHandler.swift # Background task management
│   │
│   ├── Thermal/
│   │   ├── ThermalMonitor.swift          # ProcessInfo.thermalState observer
│   │   ├── ThermalPolicy.swift           # Quality tier definitions
│   │   └── AdaptiveQualityController.swift # Applies thermal policy to camera
│   │
│   ├── Incident/
│   │   ├── IncidentDetector.swift        # Core Motion accelerometer analysis
│   │   ├── IncidentConfiguration.swift   # Sensitivity thresholds
│   │   └── ClipProtector.swift           # Marks segments as protected
│   │
│   ├── Storage/
│   │   ├── StorageManager.swift          # FIFO deletion, cap enforcement
│   │   ├── ClipRepository.swift          # CRUD for recorded clips
│   │   ├── ClipMetadata.swift            # Core Data / SwiftData entity
│   │   └── FileSystemManager.swift       # Low-level file operations
│   │
│   └── Location/
│       ├── LocationService.swift         # CLLocationManager wrapper
│       └── SpeedTracker.swift            # Speed calculation from GPS
│
├── Features/
│   ├── Recording/
│   │   ├── RecordingView.swift           # Main camera/recording screen
│   │   ├── RecordingViewModel.swift      # Recording UI state
│   │   └── RecordingOverlayView.swift    # Status indicators overlay
│   │
│   ├── Library/
│   │   ├── LibraryView.swift             # Clip grid browser
│   │   ├── LibraryViewModel.swift
│   │   ├── ClipDetailView.swift          # Single clip playback
│   │   ├── ClipDetailViewModel.swift
│   │   └── ClipThumbnailView.swift
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── SettingsViewModel.swift
│   │   ├── StorageSettingsView.swift
│   │   └── RecordingSettingsView.swift
│   │
│   ├── Onboarding/
│   │   ├── OnboardingView.swift          # First-launch permissions + legal
│   │   └── OnboardingViewModel.swift
│   │
│   └── Paywall/
│       ├── PaywallView.swift
│       └── StoreKitManager.swift
│
├── Shared/
│   ├── Extensions/
│   │   ├── AVCaptureDevice+Extensions.swift
│   │   ├── URL+Extensions.swift
│   │   ├── Date+Extensions.swift
│   │   └── FileManager+Extensions.swift
│   │
│   ├── Utilities/
│   │   ├── Logger.swift                  # OSLog wrapper
│   │   ├── Haptics.swift                 # UIFeedbackGenerator wrapper
│   │   └── Formatters.swift              # Date, file size, duration formatters
│   │
│   └── Constants/
│       ├── AppConstants.swift
│       └── StorageConstants.swift
│
├── Resources/
│   ├── Assets.xcassets/
│   ├── Localizable.xcstrings
│   └── Info.plist
│
└── Tests/
    ├── UnitTests/
    │   ├── ThermalMonitorTests.swift
    │   ├── IncidentDetectorTests.swift
    │   ├── StorageManagerTests.swift
    │   └── SegmentManagerTests.swift
    │
    └── UITests/
        ├── RecordingFlowTests.swift
        └── LibraryFlowTests.swift
```

---

## 3. Core Frameworks & Dependencies

### 3.1 Apple Frameworks (Zero third-party deps for core)

| Framework | Purpose |
|---|---|
| **AVFoundation** | Camera capture, video recording, playback |
| **VideoToolbox** | Hardware-accelerated H.265/HEVC encoding |
| **Core Motion** | Accelerometer data for incident detection |
| **Core Location** | GPS coordinates, speed data |
| **SwiftUI** | User interface |
| **SwiftData** | Clip metadata persistence (or Core Data if targeting < iOS 17) |
| **StoreKit 2** | In-app purchases |
| **OSLog** | Structured logging |
| **BackgroundTasks** | `BGProcessingTask` for maintenance |
| **UserNotifications** | Recording status, incident alerts |
| **Photos** | Export clips to Camera Roll |
| **UIKit** | `UIViewRepresentable` for camera preview, `AppDelegate` lifecycle |

### 3.2 Third-Party Dependencies (Minimal, Optional)

| Package | Purpose | Justification |
|---|---|---|
| None for v1.0 | — | Fewer dependencies = fewer points of failure for a safety-critical app |

If needed later, consider adding via SPM only: TelemetryDeck (privacy-friendly analytics) for v1.1.

---

## 4. Key Technical Decisions

### 4.1 Recording Pipeline

```
Camera Sensor
    │
    ▼
AVCaptureSession (configured via CameraService)
    │
    ├── AVCaptureVideoDataOutput ──► Live Preview (SwiftUI via CALayer)
    │
    └── AVAssetWriter ──► Segmented .mp4 files (via SegmentManager)
                              │
                              ├── Segment 1 (3 min) → saved to disk
                              ├── Segment 2 (3 min) → saved to disk
                              ├── Segment N ...
                              │
                              └── StorageManager enforces FIFO cap
```

**Why AVAssetWriter over AVCaptureMovieFileOutput:**
AVAssetWriter gives us frame-level control needed for seamless segment rotation without dropped frames, custom metadata injection (GPS, timestamp), and the ability to dynamically adjust encoding parameters when thermal state changes.

### 4.2 Segment Rotation Strategy

The SegmentManager implements a gapless rotation system. Before the current segment's target duration is reached, a new AVAssetWriter is pre-initialized and warmed up. At the rotation point, incoming sample buffers are redirected to the new writer, and the previous writer is finalized asynchronously. This ensures zero dropped frames between segments.

### 4.3 Background Execution Strategy

iOS is aggressive about killing background apps. We use a legitimate multi-signal approach. The app registers as needing background audio by playing a silent audio track or recording ambient audio (if user has audio enabled). It requests "always" location authorization and uses `allowsBackgroundLocationUpdates` on CLLocationManager. An active AVCaptureSession with audio input contributes to background eligibility. A `BGProcessingTask` handles storage cleanup when the app is suspended.

**Why this works within App Store rules:** Dashcam apps have a legitimate need for background audio recording and location tracking. Apple approves these use cases when properly justified in the App Review notes. The app will include a clear App Review information note explaining the use case.

### 4.4 Data Persistence

**SwiftData** for clip metadata (title, date, duration, file path, isProtected, GPS coordinates, thumbnail path). **File system** for actual video files stored in the app's Documents directory (backed up by iCloud if user enables). **UserDefaults** (via `@AppStorage`) for settings/preferences.

### 4.5 Concurrency Model

The app uses Swift's structured concurrency throughout. The camera pipeline runs on a dedicated `DispatchQueue` (required by AVFoundation). Core Motion processing runs on its own `OperationQueue`. All other async work uses Swift `async/await` and `Actor` isolation. The `RecordingEngine` is an `@MainActor`-isolated class that coordinates between services. Individual services like `ThermalMonitor` and `IncidentDetector` are Swift `actor` types for thread safety.

---

## 5. Background Recording — Deep Dive

### 5.1 Background Modes Required (Info.plist)

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>location</string>
    <string>processing</string>
</array>
```

### 5.2 Lifecycle Handling

```
App Active (Recording)
    │
    ├── User switches to Maps ──► scenePhase → .background
    │   ├── AVCaptureSession continues (audio bg mode keeps it alive)
    │   ├── CLLocationManager continues (location bg mode)
    │   ├── Recording continues seamlessly
    │   └── Dynamic Island / Live Activity shows recording status
    │
    ├── Incoming phone call ──► recording pauses
    │   └── Call ends ──► recording resumes automatically
    │
    ├── Memory warning ──► flush write buffers, reduce to 720p temporarily
    │
    └── System terminates app (rare if bg modes are active)
        └── On next launch: detect incomplete segment, attempt recovery
```

### 5.3 Live Activity (iOS 16.1+)

Display a Live Activity in the Dynamic Island and Lock Screen showing recording status (duration, storage remaining, thermal state indicator). This also reinforces to the system that the app is actively serving the user.

---

## 6. Error Handling Strategy

All services implement a `ServiceError` enum conforming to `LocalizedError`. Errors propagate up through the ViewModel layer to the UI. Critical errors (camera access denied, storage full, recording failure) trigger immediate user-facing alerts. Non-critical errors (GPS signal lost, minor thermal throttle) are shown as non-intrusive banners. All errors are logged via `OSLog` with appropriate log levels. A `RecordingHealthMonitor` periodically checks that all subsystems are functioning and raises alerts if anything is degraded.

---

## 7. Security & Privacy

- No network calls in v1.0 (except StoreKit for purchases)
- All video data stays on-device
- No analytics SDKs
- App Transport Security remains at default (no exceptions needed)
- Keychain used for purchase receipt validation only
- Camera preview does not render in app switcher snapshot (privacy screen)
