# Claude Code Implementation Tickets
## DashCam Pro — Step-by-Step Build Guide

**How to use this document:** Feed each ticket to Claude Code in order. Each ticket is self-contained with enough context for Claude Code to implement it. Wait for each ticket to be complete and working before moving to the next. Copy-paste the ticket text as your prompt.

---

## TICKET 1: Project Scaffolding

```
Create a new iOS project called "DashCamPro" with these requirements:

- SwiftUI app lifecycle (@main)
- Minimum deployment target: iOS 16.0
- Swift strict concurrency: Complete
- Create this folder structure inside the project:
  App/, Core/Camera/, Core/Recording/, Core/Thermal/, Core/Incident/,
  Core/Storage/, Core/Location/, Features/Recording/, Features/Library/,
  Features/Settings/, Features/Onboarding/, Features/Paywall/,
  Shared/Extensions/, Shared/Utilities/, Shared/Constants/,
  Resources/, Tests/UnitTests/, Tests/UITests/

- Add an AppDelegate.swift with UIApplicationDelegateAdaptor for
  background lifecycle hooks

- Create a DependencyContainer.swift that will hold references to
  all services (just empty placeholders for now)

- Create a TabView-based navigation with 3 tabs:
  Record (house.fill icon), Library (film.stack icon), Settings (gear icon)
  Each tab shows a placeholder view with the tab name

- Set up a global dark color scheme (.preferredColorScheme(.dark))

- Configure Info.plist with these keys:
  UIBackgroundModes: audio, location, processing
  NSCameraUsageDescription: "DashCam Pro needs camera access to record driving footage"
  NSMicrophoneUsageDescription: "DashCam Pro can record audio with your driving footage"
  NSLocationWhenInUseUsageDescription: "DashCam Pro uses your location to log speed and position"
  NSLocationAlwaysAndWhenInUseUsageDescription: "DashCam Pro needs continuous location access to record GPS data while you use other apps"

- Create a Logger.swift utility using OSLog with these subsystem categories:
  camera, recording, thermal, incident, storage, ui

- Create AppConstants.swift with:
  defaultSegmentDuration: 180 (seconds)
  defaultStorageCap: 5GB (in bytes)
  minimumSupportedDevice: "iPhone 11"
  appGroupIdentifier: (empty string placeholder)

The app should compile and run showing the tab bar with 3 placeholder screens.
All text should be white on near-black (#0A0A0A) backgrounds.
```

---

## TICKET 2: SwiftData Models

```
In the DashCamPro project, create the SwiftData models for clip storage.

Create Core/Storage/ClipMetadata.swift with two @Model classes:

RecordingSession:
- id: UUID (unique)
- startDate: Date
- endDate: Date? (nil while recording)
- totalDuration: TimeInterval
- totalSegments: Int
- wasInterrupted: Bool
- clips: [VideoClip] relationship (cascade delete)

VideoClip:
- id: UUID (unique)
- fileName: String
- filePath: String (relative to Documents/)
- thumbnailPath: String?
- startDate: Date
- endDate: Date?
- duration: TimeInterval
- fileSize: Int64
- resolution: String (store raw value)
- frameRate: Int
- codec: String (store raw value)
- isProtected: Bool (default false)
- isStarred: Bool (default false)
- protectionReason: String? (raw value)
- hasIncident: Bool (default false)
- incidentTimestamp: Date?
- peakGForce: Double?
- startLatitude: Double?
- startLongitude: Double?
- endLatitude: Double?
- endLongitude: Double?
- averageSpeed: Double?
- session: RecordingSession? (inverse relationship)

Also create supporting enums in separate files under Shared/Constants/:
- VideoResolution: String, Codable, CaseIterable (.hd720, .hd1080, .uhd4k)
  with computed properties: dimensions (CMVideoDimensions), bitrate (Int)
- VideoCodec: String, Codable (.h264, .hevc)
- IncidentSeverity: String, Codable (.minor, .moderate, .severe)
- ProtectionReason: String, Codable (.incidentDetected, .userStarred, .manualProtect)
- CameraPosition: String, Codable, CaseIterable (.backWide, .backUltraWide, .front)
- IncidentSensitivity: String, Codable, CaseIterable (.low, .medium, .high)
  with computed property: threshold (Double) — low=6.0, medium=3.0, high=1.5

Create an AppSettings struct (not SwiftData, use @AppStorage) with all
user-configurable settings as defined in the PRD. Use sensible defaults:
1080p, 30fps, HEVC, audio on, back wide camera, 3min segments, 5GB cap,
incident detection on at medium, auto-start off, dim display on.

Configure the ModelContainer in the App @main struct.
Make sure everything compiles.
```

---

## TICKET 3: Camera Service

```
In the DashCamPro project, implement the CameraService.

Create Core/Camera/CameraService.swift:
- Conforms to CameraServiceProtocol (create the protocol too)
- Manages an AVCaptureSession
- Methods:
  - configure(_ config: CameraConfiguration) async throws
  - startCapture() async throws
  - stopCapture() async
  - switchCamera(to: CameraPosition) async throws
  - updateQuality(resolution:bitrate:) async throws

CameraConfiguration struct:
- resolution: VideoResolution
- frameRate: Int
- codec: VideoCodec
- cameraPosition: CameraPosition
- audioEnabled: Bool

Implementation details:
- Use a dedicated DispatchQueue for the capture session ("com.dashcampro.camera")
- Discover available cameras using AVCaptureDevice.DiscoverySession
- Configure AVCaptureDeviceInput for video + optional audio
- Set up AVCaptureVideoDataOutput with setSampleBufferDelegate
- Set up AVCaptureAudioDataOutput if audio enabled
- Handle the sampleBuffer delegate to forward frames
  (use a published/callback pattern so the recording engine can consume frames)
- Properly handle camera permissions (check + request)
- All errors should be typed as CameraError enum

Also create Core/Camera/CameraPreviewView.swift:
- UIViewRepresentable that hosts AVCaptureVideoPreviewLayer
- Takes AVCaptureSession as input
- videoGravity = .resizeAspectFill
- Handles orientation correctly (lock to portrait but preview fills screen)

Wire the CameraService into DependencyContainer.
The RecordingView should now show a live camera preview when launched.
```

---

## TICKET 4: Basic Recording (AVAssetWriter)

```
In the DashCamPro project, implement basic video recording.

Create Core/Recording/RecordingEngine.swift:
- Uses @Observable (iOS 17) or ObservableObject
- RecordingState enum: idle, starting, recording, stopping, error
- Owns references to CameraService, and a new VideoWriter
- Methods: startRecording(), stopRecording(), reset()

Create Core/Recording/VideoWriter.swift:
- Wraps AVAssetWriter + AVAssetWriterInput (video + audio)
- Configure HEVC encoding with these settings:
  - AVVideoCodecType.hevc
  - Bitrate from VideoResolution enum
  - Hardware encoder enabled
  - Key frame interval = frameRate * 2
  - Allow frame reordering = true
- Methods:
  - setup(outputURL:resolution:frameRate:codec:audioEnabled:) throws
  - start(atSourceTime:)
  - appendVideoBuffer(_ sampleBuffer: CMSampleBuffer)
  - appendAudioBuffer(_ sampleBuffer: CMSampleBuffer)
  - finish() async throws -> URL

Save recordings to: Documents/Recordings/{date}/
File naming: clip_{shortUUID}_{sequence}_{timestamp}.mp4

Create the file directory structure on first write.

After recording stops, create a VideoClip entry in SwiftData with
all available metadata (file size, duration, dates, resolution, etc.)

Generate a thumbnail using AVAssetImageGenerator and save it to
Documents/Thumbnails/

Update RecordingView UI:
- Large red circle button at bottom center (80pt)
- White outline when idle, solid red when recording
- Tap to start/stop
- Show running timer when recording (monospaced font, large)
- Show current resolution + fps in status overlay at top

The user should be able to tap record, see the timer count up,
tap stop, and have a playable .mp4 file in the Documents directory.
```

---

## TICKET 5: Segment Rotation (Loop Recording)

```
In the DashCamPro project, implement automatic segment rotation for
continuous loop recording.

Create Core/Recording/SegmentManager.swift:
- Manages the lifecycle of recording segments
- Properties:
  - segmentDuration: TimeInterval (from settings)
  - currentSegmentIndex: Int
  - currentWriter: VideoWriter
  - nextWriter: VideoWriter? (pre-warmed for gapless rotation)

Gapless rotation algorithm:
1. When a segment reaches (segmentDuration - 2 seconds), pre-initialize
   the NEXT VideoWriter (new AVAssetWriter with new output URL)
2. At exactly segmentDuration, redirect incoming sample buffers to the
   new writer and call finish() on the old writer
3. The old writer's finish is async — don't block the sample buffer pipeline
4. After old writer finishes, save its VideoClip metadata to SwiftData
5. Increment segment index, repeat

Update RecordingEngine to use SegmentManager instead of direct VideoWriter.
Add .rotatingSegment state to RecordingState.

Update RecordingView status overlay to show:
- Current segment number
- "↻" rotation indicator that briefly flashes on segment rotation

Test: set segment duration to 10 seconds, start recording for 45 seconds,
verify you get 4-5 separate .mp4 files in the library, each approximately
10 seconds long, with no gaps between them.
```

---

## TICKET 6: Storage Manager (FIFO Auto-Delete)

```
In the DashCamPro project, implement storage cap enforcement.

Create Core/Storage/StorageManager.swift:
- Conforms to StorageManagerProtocol
- Properties:
  - storageCap: Int64 (from settings, in bytes)
  - currentUsage: Int64 (calculated from file system)

Methods:
- calculateTotalUsage() async -> Int64
  Scan Documents/Recordings/ recursively, sum file sizes
- enforceStorageCap() async throws
  If currentUsage > storageCap:
    Get all VideoClips sorted by startDate (oldest first)
    Filter out: isProtected == true, isStarred == true
    Delete files + SwiftData records until under cap
    If all remaining clips are protected, post notification warning
- deleteClip(_ clip: VideoClip) async throws
  Delete the video file, thumbnail, and SwiftData record
- deleteAllUnprotected() async throws
- availableSpace: Int64 (device free space)

Call enforceStorageCap() after every segment rotation.

Create Core/Storage/FileSystemManager.swift:
- Create directory structure on first use
- Clean up orphaned files (files with no SwiftData match)
- Clean up orphaned metadata (SwiftData records with no file)

Update Library view footer to show storage bar:
"3.2 / 5.0 GB used" with a colored progress bar
(green < 70%, yellow 70-90%, red > 90%)

Update Settings to include storage cap picker:
2 GB, 5 GB, 10 GB, 25 GB, Custom (slider)
When cap is reduced, immediately enforce the new cap.
```

---

## TICKET 7: Library & Playback

```
In the DashCamPro project, build out the full clip library and playback.

Update Features/Library/LibraryView.swift:
- Query all VideoClips from SwiftData, sorted by startDate descending
- Group by date (sections: "Today", "Yesterday", "April 10, 2026", etc.)
- 2-column LazyVGrid with clip thumbnails
- Each cell shows: thumbnail image, start time, duration, protection badge
- Filter chips at top: All / Protected / Starred
- Storage bar at bottom

Create Features/Library/ClipThumbnailView.swift:
- AsyncImage-style loading of thumbnail from file path
- Overlay with duration badge (bottom-right)
- Shield icon overlay if protected (top-left)
- Star icon overlay if starred

Create Features/Library/ClipDetailView.swift:
- Full-width video player (AVPlayer in UIViewRepresentable or VideoPlayer)
- Play/pause button overlay
- Scrub bar with current time / total time
- Below player, show metadata:
  Date, Duration, File size, Resolution
  Location (if available), Average speed (if available)
  Incident info (if applicable): severity, peak g-force
- Action buttons row: Protect/Unprotect, Star/Unstar, Share, Delete
- Share uses UIActivityViewController (standard share sheet)
- Delete shows confirmation alert, extra confirmation if protected

Add context menu (long press) on library grid items:
- Share, Protect/Unprotect, Star/Unstar, Delete

Add multi-select mode:
- "Select" button in navigation bar
- Checkmark overlay on selected clips
- Bottom toolbar: Share Selected, Delete Selected
- "Select All" / "Deselect All"

Empty state: when no clips exist, show a camera icon with
"No recordings yet. Start recording to see your clips here."
```

---

## TICKET 8: Background Recording

```
In the DashCamPro project, implement reliable background recording.

Create Core/Recording/BackgroundRecordingHandler.swift:

Audio session setup:
- AVAudioSession category: .playAndRecord
- Mode: .videoRecording
- Options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
- Activate the audio session before starting recording
- Handle interruptions (phone calls) via NotificationCenter:
  .AVAudioSession.interruptionNotification
  On interruption began: pause recording gracefully
  On interruption ended (with shouldResume): resume recording

Location background:
- Create Core/Location/LocationService.swift
- CLLocationManager with:
  desiredAccuracy: kCLLocationAccuracyHundredMeters (power saving)
  distanceFilter: 10 meters
  allowsBackgroundLocationUpdates = true
  showsBackgroundLocationIndicator = true (blue bar)
  pausesLocationAutomatically = false
- Store location updates in memory, attach to clip metadata on segment save
- Create SpeedTracker that computes speed from CLLocation.speed

App lifecycle handling in AppDelegate:
- applicationDidEnterBackground: log event, verify capture session still running
- applicationWillTerminate: finalize current segment, save metadata
- applicationDidReceiveMemoryWarning: flush buffers, reduce quality to 720p

Handle interruptions in RecordingEngine:
- Phone call: AVAudioSession interruption → pause writing → resume on end
- Siri activation: same as phone call
- Memory warning: reduce quality, flush write buffers

Update RecordingView to show background-readiness indicator:
"Background recording enabled ✓" in settings

Create a Live Activity (ActivityKit) for iOS 16.1+:
- DashCamWidgetAttributes with: startTime, segmentCount, storageUsed
- Compact presentation: red circle + "REC" + timer
- Expanded presentation: timer + storage used + thermal indicator
- Lock screen: same as expanded
- Update Live Activity on each segment rotation

Test: start recording → press home → open Safari → wait 5 minutes →
return to app → verify recording has 5+ minutes of continuous footage.
```

---

## TICKET 9: Incident Detection

```
In the DashCamPro project, implement accelerometer-based incident detection.

Create Core/Incident/IncidentDetector.swift:
- Uses CMMotionManager for accelerometer data
- Starts accelerometer updates at 60Hz on its own OperationQueue
- Calculates total g-force: sqrt(x² + y² + z²) - 1.0 (subtract gravity)
- Compares against sensitivity threshold (from IncidentSensitivity enum)
- Debounce: ignore subsequent triggers for 10 seconds after an incident
- Publishes incidents via Combine publisher or AsyncStream

IncidentEvent struct:
- timestamp: Date
- severity: IncidentSeverity (calculated from peak g-force)
- peakGForce: Double
- latitude: Double?
- longitude: Double?

Create Core/Incident/ClipProtector.swift:
- On incident: mark current VideoClip as protected with reason .incidentDetected
- Also protect the PREVIOUS segment (for pre-incident buffer)
- Set hasIncident = true, incidentTimestamp, peakGForce on the clip
- Protected clips are excluded from FIFO deletion

Integrate with RecordingEngine:
- Start IncidentDetector when recording starts
- Stop when recording stops
- On incident event:
  1. Call ClipProtector
  2. Trigger haptic feedback (UIImpactFeedbackGenerator .heavy)
  3. Post local notification if app is backgrounded
  4. Update UI with incident animation

Recording screen incident UI:
- Yellow border flash animation (2 quick flashes)
- Status overlay briefly shows "⚠ INCIDENT SAVED" for 3 seconds
- Sound effect (short alert tone) if audio is enabled

Settings:
- Incident detection on/off toggle
- Sensitivity picker: Low / Medium / High with descriptions:
  Low: "Detects severe impacts only (6g+)"
  Medium: "Detects hard braking and impacts (3g+)"  
  High: "Detects any sudden movement (1.5g+)"

Write unit tests for IncidentDetector:
- Test detection at each threshold
- Test debounce behavior
- Test g-force calculation
- Test that normal vibrations don't trigger (use sample data:
  random values between -0.3 and 0.3 for x/y, -0.7 to -1.3 for z)
```

---

## TICKET 10: Thermal Management

```
In the DashCamPro project, implement the thermal monitoring and
adaptive quality system.

Create Core/Thermal/ThermalMonitor.swift:
- Observes ProcessInfo.thermalStateDidChangeNotification
- Publishes current thermal state via Combine or @Observable
- Logs all state transitions with timestamps via OSLog
- Actor-isolated for thread safety

Create Core/Thermal/ThermalPolicy.swift:
- Defines the 4-tier response system:

  .nominal → no changes
  .fair → frameRate: 24fps, bitrate: -20%, display dim if enabled
  .serious → resolution: 720p, frameRate: 24fps, bitrate: 1.5Mbps,
              display: minimum brightness, reduce Core Motion to 10Hz,
              reduce GPS frequency
  .critical → resolution: 720p, frameRate: 15fps, bitrate: 800Kbps,
               display: off, pause incident detection, GPS: significant
               changes only

- Each tier defined as a struct with all parameters
- Recovery: when state improves, wait 60 seconds before stepping up one tier

Create Core/Thermal/AdaptiveQualityController.swift:
- Subscribes to ThermalMonitor
- On state change: look up ThermalPolicy for new state
- Apply changes to CameraService (resolution, framerate, bitrate)
- Apply display changes via UIScreen.main.brightness
- Apply Core Motion changes to IncidentDetector
- Apply GPS changes to LocationService
- Track time spent in each tier (for developer stats)

Integrate with RecordingEngine:
- Start ThermalMonitor when recording starts
- AdaptiveQualityController runs continuously during recording
- Stop when recording stops

Recording screen UI updates:
- Thermal indicator dot in status overlay:
  Green (.nominal), Yellow (.fair), Orange (.serious), Red (.critical)
- At .serious: show small text "Quality reduced — device is warm"
- At .critical: show text "Minimum quality — device is hot"
  + vibrate alert + notification if backgrounded

Settings:
- "Adaptive thermal management" toggle (on by default)
- When off: quality never auto-reduces, but user accepts thermal risk

Write unit tests for ThermalPolicy:
- Verify correct parameters for each tier
- Verify recovery delay logic
```

---

## TICKET 11: Onboarding Flow

```
In the DashCamPro project, create the first-launch onboarding experience.

Create Features/Onboarding/OnboardingView.swift:
- 6-screen TabView with page indicator dots
- Track completion in @AppStorage("hasCompletedOnboarding")
- If already completed, skip straight to main app

Screen 1 - Welcome:
- Large app icon (SF Symbol "video.circle.fill" as placeholder)
- "DashCam Pro" title
- "Your phone is your dashcam." subtitle
- "Get Started" button → advance to screen 2

Screen 2 - Camera:
- SF Symbol "camera.fill" large illustration
- "Camera Access Required"
- "DashCam Pro uses your camera to record driving footage."
- "Enable Camera" button → trigger AVCaptureDevice.requestAccess
- "Skip" small button

Screen 3 - Microphone:
- SF Symbol "mic.fill" large illustration
- "Record Audio (Optional)"
- "Capture audio alongside your video footage."
- Small disclaimer: "Audio recording laws vary by location."
- "Enable Microphone" / "Skip" buttons

Screen 4 - Location:
- SF Symbol "location.fill" large illustration
- "Track Speed & Location"
- "Log your speed and GPS coordinates with each clip."
- "Used only on-device. Never uploaded or shared."
- "Enable Location" button → request .authorizedAlways
- "Skip" button

Screen 5 - Legal:
- SF Symbol "doc.text.fill" illustration
- "Legal Notice"
- Scrollable text: "By using DashCam Pro, you acknowledge that
  dashboard camera and audio recording laws vary by jurisdiction.
  You are solely responsible for ensuring compliance with all
  applicable local, state, and federal laws. DashCam Pro does not
  provide legal advice."
- "I Understand & Agree" button (must scroll to bottom to enable)

Screen 6 - Ready:
- SF Symbol "checkmark.circle.fill" in green
- "You're Ready to Roll"
- Summary of enabled permissions
- "Start Recording" large button → dismiss onboarding, go to recording
  screen, auto-start recording

Navigation: user can swipe between screens or use buttons.
"Back" button on screens 2-5.
Page dots at bottom show progress.
All screens use dark theme (#0A0A0A background, white text).
```

---

## TICKET 12: Settings & Paywall

```
In the DashCamPro project, build the full settings screen and in-app purchase.

Update Features/Settings/SettingsView.swift with grouped Form:

Section "Recording":
- Resolution picker: 720p / 1080p / 4K (4K shows "Pro" badge if not purchased)
- Frame rate picker: 24fps / 30fps
- Audio recording toggle
- Camera picker: Back Wide / Back Ultra Wide / Front

Section "Segments":
- Clip duration picker: 1 min / 3 min / 5 min / 10 min
- Storage limit picker: 2 GB / 5 GB / 10 GB / 25 GB / Custom
  (anything above 2 GB shows "Pro" badge if not purchased)

Section "Incident Detection":
- Enable/disable toggle (shows "Pro" badge if not purchased)
- Sensitivity picker with descriptions

Section "Power Management":
- Auto-dim display toggle
- Adaptive thermal management toggle

Section "Behavior":
- Auto-record on app launch toggle

Section "About":
- Version number (tap 3x for developer stats)
- Privacy Policy (opens Safari)
- Terms of Use (opens Safari)
- Contact Support (opens mailto:)
- Restore Purchases button

All settings persist via @AppStorage and take effect immediately
on the active recording (if one is running).

Create Features/Paywall/StoreKitManager.swift:
- StoreKit 2 implementation
- Product IDs: "com.dashcampro.pro.monthly", "com.dashcampro.pro.lifetime"
- Load products, handle purchases, verify entitlements
- Check entitlement status via Transaction.currentEntitlements
- Restore purchases support

Create Features/Paywall/PaywallView.swift:
- Presented as sheet when user taps a Pro-gated feature
- "Unlock DashCam Pro" title
- List of Pro features with checkmarks
- Two purchase buttons: "$2.99/month" and "$9.99 one-time"
- "Restore Purchases" link
- "No thanks" dismiss button
- Terms and privacy policy links at bottom (required by Apple)

Free tier limits (enforced in relevant services):
- Max storage cap: 2 GB
- Max resolution: 720p
- Incident detection: disabled
```

---

## TICKET 13: Polish & Final Integration

```
In the DashCamPro project, do a full polish pass on the UI and
fix any integration issues.

Recording screen polish:
- Record button: 80pt circle, white outline when idle, solid red when recording
- Pulse animation on red button: scale 1.0 → 1.05 → 1.0, 2s loop
- Status overlay at top with semi-transparent dark background + corner radius:
  Line 1: "● REC" (red) + timer + resolution + fps
  Line 2: Thermal dot + storage used/cap
- Mute toggle button (bottom-left): mic.fill / mic.slash.fill
- Camera flip button (bottom-right): camera.rotate.fill
- Camera flip animation: 3D rotation transition

Library polish:
- Smooth thumbnail loading with placeholder shimmer
- Pull to refresh (re-scan file system)
- Swipe actions on clips (swipe left for delete)
- Tap animation on grid items

General polish:
- Ensure ALL views use the dark color palette:
  Background #0A0A0A, Surface #1A1A1A, Surface Elevated #2A2A2A
  Primary Red #FF3B30, Green #30D158, Warning #FF9F0A
- Consistent 16pt padding throughout
- SF Pro system font everywhere (no custom fonts)
- All interactive elements have minimum 44pt touch target
- Haptic feedback: medium impact on record start/stop,
  selection feedback on settings changes,
  heavy impact on incident detection

Navigation:
- Tab bar with filled SF Symbols
- Smooth transitions between views

Error states:
- Camera permission denied: full-screen message with "Open Settings" button
- Storage full (all clips protected): alert with explanation
- Recording failed: alert with "Try Again" and "Report Issue"

Verify the complete flow works end-to-end:
1. Fresh install → onboarding → permissions → start recording
2. Record for 2 minutes → see segments rotate
3. Background app → come back → still recording
4. Stop → clips in library → play one → share it
5. Settings → change resolution → record again → verify new resolution
6. Storage cap hit → old clips deleted → protected clips survive
```

---

## TICKET 14: Testing Suite

```
In the DashCamPro project, create comprehensive unit and UI tests.

Unit Tests (Tests/UnitTests/):

ThermalPolicyTests.swift:
- testNominalTierReturnsFullQuality
- testFairTierReducesFrameRate
- testSeriousTierForcesLowRes
- testCriticalTierMinimizesEverything
- testRecoveryWaits60Seconds

IncidentDetectorTests.swift:
- testDetectsAtLowSensitivity (6g+ trigger)
- testDetectsAtMediumSensitivity (3g+ trigger)
- testDetectsAtHighSensitivity (1.5g+ trigger)
- testDebounceIgnoresSecondEvent
- testNormalVibrationsNoFalsePositive
- testGForceCalculation
(Use a MockMotionManager that injects fake accelerometer data)

StorageManagerTests.swift:
- testFIFODeletesOldestFirst
- testProtectedClipsSurviveFIFO
- testStarredClipsSurviveFIFO
- testExactCapBoundary
- testAllProtectedShowsWarning
- testReducedCapTriggersImmediateCleanup
(Use a temporary directory for test files)

SegmentManagerTests.swift:
- testSegmentRotatesAtDuration
- testSequentialNumbering
- testFileNamingConvention
- testMetadataSavedAfterRotation

RecordingStateTests.swift:
- testValidTransitions (idle→starting→recording→stopping→idle)
- testInvalidTransitionThrows (idle→stopping)
- testErrorRecovery (error→reset→idle)

UI Tests (Tests/UITests/):

OnboardingFlowTests.swift:
- testCompleteOnboardingFlow: swipe through all 6 screens

RecordingFlowTests.swift:
- testStartAndStopRecording: tap record → wait → tap stop → verify

LibraryFlowTests.swift:
- testClipAppearsAfterRecording: record → stop → switch to library tab → verify clip exists
- testClipDeletion: long press → delete → confirm → verify removed

SettingsFlowTests.swift:
- testChangeResolution: navigate → change → verify persisted

Target: 80%+ code coverage on Core/ layer.
Run all tests and fix any failures.
```

---

## TICKET 15: App Store Preparation

```
In the DashCamPro project, prepare everything needed for App Store submission.

Create/update the following:

App Icon:
- For now, create a simple placeholder using SF Symbols
  or a basic SwiftUI-rendered icon: dark background (#0A0A0A)
  with a red recording dot and a simplified camera lens shape
- Export at all required sizes for the Assets catalog
  (or just set a 1024x1024 and let Xcode auto-generate)

Launch Screen:
- Simple: App name "DashCam Pro" centered on #0A0A0A background
- Thin red horizontal line underneath the text
- Configure in Info.plist or as LaunchScreen storyboard

Privacy Manifest (PrivacyInfo.xcprivacy):
- Required APIs used: UserDefaults, FileManager, CLLocationManager
- No tracking, no third-party SDKs
- Data collected: Camera (functionality), Location (functionality),
  Microphone (functionality) — all on-device only

App Store metadata (create a file AppStoreMetadata.md):
- App name: DashCam Pro
- Subtitle: "Your Phone. Your Dashcam."
- Category: Navigation (primary), Utilities (secondary)
- Keywords: dashcam, dash cam, car camera, driving recorder, incident,
  loop recording, car DVR, road safety, drive recorder, auto camera
- Description (4000 char max): write compelling copy hitting key
  differentiators: thermal management, background recording, incident
  detection, privacy-first, no account needed
- What's New (for v1.0): "Initial release"
- App Review Notes: "This app uses background audio and location to
  function as a dashboard camera. Recording must continue when the user
  switches to navigation or music apps. Background location is used to
  log GPS coordinates and speed for each recording clip. The audio
  background mode is required to keep the camera capture session active.
  Test account: not required — all features work without an account."

Verify the app builds in Release configuration with no warnings.
Run the full test suite one final time.
```

---

## Implementation Order Summary

| Order | Ticket | Depends On | Est. Time |
|---|---|---|---|
| 1 | Project Scaffolding | Nothing | 1-2 hours |
| 2 | SwiftData Models | Ticket 1 | 1-2 hours |
| 3 | Camera Service | Ticket 1 | 2-3 hours |
| 4 | Basic Recording | Tickets 2, 3 | 3-4 hours |
| 5 | Segment Rotation | Ticket 4 | 2-3 hours |
| 6 | Storage Manager | Tickets 2, 5 | 2-3 hours |
| 7 | Library & Playback | Tickets 2, 4 | 3-4 hours |
| 8 | Background Recording | Tickets 4, 5 | 4-5 hours |
| 9 | Incident Detection | Tickets 4, 5 | 3-4 hours |
| 10 | Thermal Management | Tickets 3, 4 | 3-4 hours |
| 11 | Onboarding | Ticket 1 | 2-3 hours |
| 12 | Settings & Paywall | All above | 3-4 hours |
| 13 | Polish & Integration | All above | 4-6 hours |
| 14 | Testing Suite | All above | 4-6 hours |
| 15 | App Store Prep | All above | 2-3 hours |

**Total estimated: ~40-55 hours of Claude Code time**
