# Sprint Plan & Development Roadmap
## DashCam Pro

**Version:** 1.0
**Date:** April 12, 2026
**Methodology:** 2-week sprints, Kanban-style within each sprint

---

## Phase 0 — Project Setup (Sprint 0, Days 1-3)

**Goal:** Xcode project scaffolded, all infrastructure in place, zero features but everything compiles and runs.

### Tickets

**S0-1: Initialize Xcode project**
- Create new Xcode project: "DashCamPro", iOS 16.0 minimum, Swift, SwiftUI lifecycle
- Configure bundle ID, team, signing
- Set up folder structure matching architecture doc
- Add .gitignore for Xcode/Swift
- Initial commit

**S0-2: Configure project settings**
- Info.plist: add all required background modes (audio, location, processing)
- Info.plist: add NSCameraUsageDescription, NSMicrophoneUsageDescription, NSLocationWhenInUseUsageDescription, NSLocationAlwaysAndWhenInUseUsageDescription
- Configure build settings: Swift strict concurrency checking = Complete
- Enable HEVC encoding capability

**S0-3: Set up dependency injection container**
- Create `DependencyContainer.swift` with protocol-based service registration
- Create all service protocols (empty implementations)
- Verify app compiles with DI container wired up

**S0-4: Set up logging infrastructure**
- Create `Logger.swift` OSLog wrapper with categories: camera, recording, thermal, incident, storage, ui
- Add log statements to app lifecycle events

**S0-5: Configure SwiftData schema**
- Create `RecordingSession` and `VideoClip` models
- Create ModelContainer configuration
- Verify schema migration works

**S0-6: Set up tab-based navigation**
- Create TabView with Record, Library, Settings tabs
- Placeholder views for each tab
- Dark color scheme applied globally

---

## Phase 1 — Camera & Basic Recording (Sprint 1, Weeks 1-2)

**Goal:** Camera preview works, can record a single video file, can play it back.

### Tickets

**S1-1: Implement CameraService**
- AVCaptureSession setup and teardown
- Camera device discovery (back wide, ultrawide, front)
- Configure video resolution and frame rate
- Camera permission request flow
- Protocol conformance: CameraServiceProtocol

**S1-2: Implement camera preview in SwiftUI**
- UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
- Correct orientation handling (landscape consideration for car mount)
- Preview fills screen edge-to-edge

**S1-3: Implement basic recording with AVAssetWriter**
- Single-file recording (no segmentation yet)
- HEVC encoding configuration
- Start/stop recording
- Save to Documents/Recordings/
- Audio capture integration

**S1-4: Build Recording screen UI**
- Camera preview (full bleed)
- Record button (large, centered at bottom)
- Start/stop state management
- Recording timer display
- Mute toggle button

**S1-5: Basic clip playback**
- AVPlayer integration in ClipDetailView
- Play/pause controls
- Scrub bar
- Navigate from Library → Clip Detail

**S1-6: Build basic Library screen**
- Query SwiftData for all clips
- Display in 2-column grid with thumbnails
- Generate thumbnails from video files using AVAssetImageGenerator
- Show timestamp and duration

### Sprint 1 Definition of Done
- Can open app, see camera preview
- Can tap record, see timer counting
- Can stop recording, clip appears in library
- Can tap clip in library, watch it play back

---

## Phase 2 — Loop Recording & Storage (Sprint 2, Weeks 3-4)

**Goal:** Continuous recording with automatic segment rotation and storage cap enforcement.

### Tickets

**S2-1: Implement SegmentManager**
- Segment rotation logic (configurable duration: 1/3/5/10 min)
- Gapless writer rotation (pre-warm next AVAssetWriter)
- Save segment metadata to SwiftData on rotation
- Segment file naming convention

**S2-2: Implement StorageManager**
- Calculate total recording storage usage
- FIFO deletion of oldest unprotected clips
- Storage cap configuration (UserDefaults)
- Storage usage UI in Library footer

**S2-3: Implement RecordingEngine state machine**
- Full state machine: idle → starting → recording → rotatingSegment → stopping → error
- Coordinate CameraService + SegmentManager
- Handle edge cases: camera interrupted, disk full, permission revoked

**S2-4: Segment-aware Library UI**
- Group clips by session (date sections)
- Show segment number within session
- Long-press context menu: Share, Delete, Protect
- Multi-select + bulk delete

**S2-5: Settings screen — Recording section**
- Resolution picker (720p / 1080p / 4K)
- Frame rate picker (24 / 30)
- Segment duration picker
- Storage cap slider/picker
- Audio toggle
- Camera selection
- Persist all settings via @AppStorage

**S2-6: File system management**
- Create directory structure on first launch
- Cleanup orphaned files (no metadata match)
- Handle disk-full errors gracefully

### Sprint 2 Definition of Done
- Recording automatically creates 3-minute segments
- Old clips are auto-deleted when storage cap is reached
- All recording settings are configurable and persist between launches
- Can record for 30+ minutes with correct segment rotation

---

## Phase 3 — Background Recording (Sprint 3, Weeks 5-6)

**Goal:** Recording survives app backgrounding, phone calls, and screen lock.

### Tickets

**S3-1: Implement BackgroundRecordingHandler**
- Configure background audio session (AVAudioSession category .playAndRecord)
- Background location updates (CLLocationManager.allowsBackgroundLocationUpdates)
- Handle audio session interruptions (phone calls, Siri)

**S3-2: Implement LocationService**
- CLLocationManager setup with appropriate accuracy
- Background location capability
- Speed tracking from GPS data
- Store location data in clip metadata

**S3-3: App lifecycle handling**
- scenePhase monitoring (.active → .background → .inactive)
- Maintain recording through all transitions
- Resume recording after phone call interruption
- Handle memory warnings (flush buffers, reduce quality)

**S3-4: Live Activity integration**
- ActivityKit Live Activity for recording status
- Dynamic Island compact + expanded views
- Lock Screen Live Activity
- Update with timer, storage, thermal state

**S3-5: Local notifications**
- "Recording started" confirmation
- "Recording interrupted" alert with reason
- "Storage almost full" warning at 90% cap
- "Incident detected" notification when backgrounded
- Notification categories with actions (Stop Recording, Open App)

**S3-6: Background reliability testing**
- Automated test: start recording → background app → wait 10 min → verify recording
- Test with Maps running in foreground
- Test with Spotify playing
- Test phone call interruption → resume
- Test screen lock → verify continued recording

### Sprint 3 Definition of Done
- Can start recording, switch to Maps for 30+ minutes, switch back — recording intact
- Live Activity shows in Dynamic Island during background recording
- Phone call pauses then resumes recording
- Recording survives screen lock

---

## Phase 4 — Incident Detection & Thermal Management (Sprint 4, Weeks 7-8)

**Goal:** Accelerometer-based incident detection with clip protection, and full thermal adaptive quality system.

### Tickets

**S4-1: Implement IncidentDetector**
- Core Motion accelerometer setup
- G-force calculation from raw accelerometer data
- Configurable sensitivity thresholds (low/medium/high)
- Debounce logic (don't fire multiple incidents within 10 seconds)

**S4-2: Implement ClipProtector**
- On incident: mark current segment as protected
- Also protect previous segment (for 30-second buffer before impact)
- Protected clips excluded from FIFO deletion
- Protection reason metadata

**S4-3: Incident UI & feedback**
- Yellow border flash animation on incident
- Haptic feedback (heavy impact)
- Status bar shows "INCIDENT SAVED" briefly
- Notification when backgrounded
- Incident badge on clip thumbnails in library

**S4-4: Implement ThermalMonitor**
- ProcessInfo.thermalState observation
- Publish thermal state changes
- Thermal state history logging

**S4-5: Implement AdaptiveQualityController**
- Thermal policy tiers (nominal → fair → serious → critical)
- Dynamic resolution/framerate/bitrate adjustment
- Gradual recovery with 60-second delay
- Display dimming at higher thermal states
- UI indicators for current thermal state

**S4-6: Incident detection settings**
- Enable/disable toggle
- Sensitivity picker with descriptions
- Test mode: shake phone to simulate incident (debug builds only)

### Sprint 4 Definition of Done
- Shaking the phone while recording triggers incident detection
- Protected clips survive FIFO deletion
- Simulated thermal state changes cause visible quality adjustments
- Recording sustains 1+ hour on physical device without thermal shutdown

---

## Phase 5 — Onboarding, Paywall & Polish (Sprint 5, Weeks 9-10)

**Goal:** First-launch experience, monetization, and UI polish for App Store readiness.

### Tickets

**S5-1: Implement onboarding flow**
- 6-screen onboarding sequence
- Permission requests at appropriate screens
- Legal disclaimer acceptance
- "Always" location permission explanation
- Skip to main if permissions already granted (returning user)

**S5-2: Implement StoreKit 2 paywall**
- Define products: Pro monthly ($2.99), Pro lifetime ($9.99)
- StoreKit 2 product loading and purchase flow
- Receipt validation
- Restore purchases
- Gate features: storage cap > 2GB, resolution > 720p, incident detection
- Paywall UI screen

**S5-3: Polish Recording screen**
- Smooth animations (record button pulse, state transitions)
- Camera flip animation
- Status overlay polish (blur background, rounded corners)
- Orientation lock to portrait

**S5-4: Polish Library screen**
- Smooth thumbnail loading (async)
- Pull-to-refresh
- Empty state illustration
- Storage bar with color coding (green → yellow → red)

**S5-5: Polish Settings screen**
- Grouped list styling matching iOS conventions
- "About" section with version, privacy policy link, support email
- "Developer stats" hidden screen (triple-tap version)
- Rate app prompt (after 5 successful recording sessions)

**S5-6: App icon & launch screen**
- Design app icon (dashcam lens motif, dark background, red accent)
- Launch screen (simple logo on black)
- Configure all icon sizes in Assets catalog

### Sprint 5 Definition of Done
- New user can go through onboarding and start recording in < 60 seconds
- Free tier limits are enforced, paywall appears at appropriate gates
- Purchases work in Sandbox environment
- App feels polished and professional

---

## Phase 6 — Testing, QA & App Store Submission (Sprint 6, Weeks 11-12)

**Goal:** Full test coverage, bug fixes, performance optimization, and App Store submission.

### Tickets

**S6-1: Unit test suite**
- ThermalMonitor tests with mocked ProcessInfo
- IncidentDetector tests with simulated accelerometer data
- StorageManager tests with file system mocks
- SegmentManager tests with timing verification
- Target: 80%+ code coverage on Core/ layer

**S6-2: UI test suite**
- Recording flow: start → verify timer → stop → verify clip in library
- Library flow: browse → play → delete
- Settings flow: change settings → verify persistence
- Onboarding flow: complete all screens

**S6-3: Performance profiling**
- Instruments: CPU/GPU profiling during recording
- Instruments: Memory leaks check
- Instruments: Energy log during 1-hour recording
- Instruments: Thermal state monitoring
- Fix any performance issues found

**S6-4: Real-device testing matrix**
- Test on iPhone 11 (minimum supported)
- Test on iPhone 13 (target device)
- Test on iPhone 15 Pro (latest)
- Test each: basic recording, background, thermal, incident detection
- Document results in test report

**S6-5: App Store preparation**
- Write App Store description and keywords
- Create screenshots (6.7", 6.1", 5.5")
- Write App Review notes explaining background mode usage
- Privacy nutrition label configuration
- App category: Navigation (or Utilities)

**S6-6: Submit to App Store**
- Archive build
- Upload to App Store Connect
- Submit for review
- Monitor review feedback
- Address any rejection reasons

### Sprint 6 Definition of Done
- All unit tests pass, 80%+ coverage
- All UI tests pass
- No memory leaks or performance regressions
- App Store submission accepted for review

---

## Post-Launch Roadmap

| Version | Timeline | Features |
|---|---|---|
| v1.0 | Sprints 1-6 | MVP: Loop recording, background, incident detection, thermal management |
| v1.1 | +4 weeks | GPS/speed overlay on video, CarPlay, auto-start on Bluetooth, cloud backup |
| v1.2 | +8 weeks | Dual camera, Apple Watch companion, widgets |
| v2.0 | +16 weeks | AI incident classification, ADAS features, social/community |
