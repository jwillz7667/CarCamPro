# Changelog

All notable changes to CarCam Pro are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Full SwiftUI UI implementation matching the Claude Design handoff:
  onboarding, home dashboard, live HUD, map, trips, incident playback,
  settings.
- `CCTheme` design-token system + a family of SwiftUI primitives
  (`CCLabel`, `CCNum`, `CCGauge`, `CCTicks`, `CCRecDot`, `CCCrosshair`,
  `CCFeedPlaceholder`, `CCPanel`, `CCTopBar`, `CCTabBar`).
- `ThermalMonitor` (four-tier policy + 60 s recovery hysteresis).
- `IncidentDetector` actor (Core Motion @ 60 Hz, g-force threshold
  trigger with 10 s debounce).
- `LocationService` wrapper around `CLLocationManager` with background
  updates + automotive-grade configuration.
- First-launch onboarding gate with live horizon calibration.
- `RecordingEngine` extensions: thermal tier application, incident-driven
  clip protection, location-sample ingestion, per-session telemetry
  accumulators (distance, peak speed, incident count, locked count).
- `StorageManager.protectLatestClip(in:reason:)` for LOCK button + incident
  event clip protection.
- `Info.plist`: `NSMotionUsageDescription`, `NSPhotoLibraryAddUsageDescription`,
  forced dark `UIUserInterfaceStyle`, hidden status bar in Live HUD.

### Changed
- `RecordingSession` gains distance / peak-speed / locked-clip / incident-count
  / route / end-location fields for the Trips archive.
- `AppLogger` marked `nonisolated` to prevent Swift 6 main-actor crossings
  from background queues.
- `SampleBufferDelegate` explicitly `nonisolated` — resolves Swift 6 isolation
  warnings when callbacks arrive from AVFoundation's private queue.

### Removed
- Legacy placeholder views (`RecordingView`, `LibraryPlaceholderView`,
  `SettingsPlaceholderView`, `StorageBarView`) — superseded by the full
  Claude-Design-derived implementation.

## [0.1.0] — 2026-04-12

### Added
- Initial scaffolding: `CameraService`, `RecordingEngine`, `SegmentManager`,
  `VideoWriter`, `StorageManager`, `FileSystemManager`.
- SwiftData models: `RecordingSession`, `VideoClip`.
- Supporting constants: `VideoResolution`, `VideoCodec`, `CameraPosition`,
  `IncidentSensitivity`, `IncidentSeverity`, `ProtectionReason`,
  `RecordingState`, `AppConstants`, `AppSettings`.
- Basic 3-tab placeholder UI (Record / Library / Settings).
- `Info.plist` with required background modes (audio, location, processing)
  and usage strings (camera, microphone, location).
- Unit test scaffolding.
