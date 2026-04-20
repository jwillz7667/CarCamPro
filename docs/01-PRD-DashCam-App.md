# Product Requirements Document (PRD)
## DashCam Pro — iOS Dashcam Application

**Version:** 1.0
**Date:** April 12, 2026
**Status:** Draft → Ready for Engineering

---

## 1. Executive Summary

DashCam Pro is a native iOS application that transforms an iPhone into a fully-functional dashboard camera. The app provides continuous loop recording, automatic incident detection via accelerometer, and reliable background operation — allowing drivers to use their phone for navigation and music while recording is active.

The app targets the ~80% of drivers who don't own a dedicated dashcam but already have a phone mounted on their dashboard. By solving the overheating, battery drain, and background reliability problems that plague existing phone dashcam apps, DashCam Pro aims to become the category leader on the App Store.

---

## 2. Problem Statement

Dedicated dashcams cost $50–$300, require installation, and add another device to manage. Most drivers already mount their phone on the dashboard in the perfect dashcam position. Existing phone dashcam apps fail because they overheat the phone within 20–40 minutes of recording, drain the battery even when plugged in, stop recording when the user switches to another app, and provide no automatic incident detection or clip protection.

DashCam Pro solves all four problems.

---

## 3. Target Users

**Primary Persona — "Daily Commuter Dana":** Drives 30–90 minutes daily, uses phone for navigation, wants dashcam footage "just in case" but doesn't want another device. Tech-comfortable but not a power user.

**Secondary Persona — "Rideshare Driver Ray":** Drives 4–8 hours/day for Uber/Lyft, needs continuous recording for liability protection, cannot afford the phone overheating mid-shift.

**Tertiary Persona — "Road Trip Riley":** Takes long drives, wants scenic footage and incident protection, values GPS/speed overlay for travel documentation.

---

## 4. MVP Feature Set (v1.0)

### 4.1 Continuous Loop Recording
- Record continuously using the rear-facing (wide-angle) camera
- Configurable loop duration: 1 min, 3 min, 5 min, 10 min segments
- Configurable total storage cap: 2 GB, 5 GB, 10 GB, 25 GB, Custom
- Automatic FIFO (first-in-first-out) deletion when storage cap is reached
- Each segment saved as an individual .mp4 file for easy management
- Recording indicator visible in Dynamic Island / status bar

### 4.2 Background Recording
- Continue recording when the app is moved to background
- Leverage `AVCaptureSession` + background audio session + location updates to maintain recording
- Survive app switches to Maps, Spotify, Phone, Messages, etc.
- Graceful handling of memory warnings (flush buffer, reduce quality temporarily)
- Automatic resume after incoming phone calls
- Local notification if recording is interrupted for any reason

### 4.3 Automatic Incident Detection
- Use Core Motion accelerometer data to detect sudden deceleration/impacts
- Configurable sensitivity: Low (hard crash only), Medium (hard braking + crash), High (any sudden movement)
- When triggered: immediately lock/protect the current segment + 30 seconds before and after
- Protected clips are excluded from FIFO auto-deletion
- Visual + haptic alert when incident is detected
- Optional: automatic emergency contact notification (v1.1)

### 4.4 Thermal & Battery Management
- Adaptive quality system that monitors `ProcessInfo.thermalState`
- Four thermal tiers with automatic quality adjustment (detailed in Architecture doc)
- Target: sustain recording for 2+ hours on iPhone 13 and later without thermal shutdown
- Power-efficient encoding using hardware H.265 (HEVC) via VideoToolbox
- Display dimming during active recording (configurable)
- Battery level monitoring with low-battery warnings and graceful shutdown

### 4.5 Clip Library & Management
- Grid view of all recorded segments, organized by date/time
- Filter: All / Protected (incidents) / Starred
- Playback with scrubbing
- Share individual clips or date ranges via standard iOS share sheet
- Bulk delete, bulk export
- Storage usage indicator with breakdown

### 4.6 Settings & Configuration
- Video resolution: 1080p (default), 720p (battery saver), 4K (short recording only)
- Frame rate: 30fps (default), 24fps (battery saver)
- Audio recording toggle (on by default)
- Camera selection: back wide, back ultrawide, front (for cabin cam)
- Incident sensitivity adjustment
- Storage cap management
- Auto-start recording on app launch toggle
- Auto-start recording on CarPlay/Bluetooth connection (v1.1)

---

## 5. Out of Scope for v1.0 (Future Roadmap)

- Cloud backup / sync (v1.1)
- Dual camera recording (front + rear simultaneously) (v1.2)
- Speed/GPS overlay burned into video (v1.1)
- Apple Watch companion for remote start/stop (v1.2)
- CarPlay integration (v1.1)
- AI-powered incident classification (v2.0)
- ADAS features like lane departure warning (v2.0)
- Social sharing / community features (v2.0)

---

## 6. Success Metrics

| Metric | Target (90 days post-launch) |
|---|---|
| App Store rating | ≥ 4.5 stars |
| Thermal shutdown rate | < 2% of sessions > 1 hour |
| Background recording reliability | > 98% uptime when backgrounded |
| Incident detection accuracy | > 90% true positive, < 10% false positive |
| Daily active recording sessions | Growing 10% week-over-week |
| Crash-free rate | > 99.5% |
| Average session recording duration | > 20 minutes |

---

## 7. Technical Constraints

- **Minimum iOS version:** iOS 16.0 (for background task APIs and modern AVFoundation features)
- **Minimum device:** iPhone 11 (A13 chip required for efficient HEVC encoding)
- **Storage:** App must never exceed user-configured storage cap
- **Privacy:** Camera and microphone permissions required; location permission required for GPS metadata; no data leaves the device in v1.0
- **App Review:** Must comply with Apple's background execution policies (legitimate use of background audio + location)

---

## 8. Privacy & Legal Considerations

- Recording audio in vehicles may be subject to consent laws (varies by jurisdiction)
- App must display clear "Recording in Progress" indicators
- First-launch onboarding must include consent/legal disclaimer
- Metadata (GPS, speed) stored locally only
- No analytics or telemetry in v1.0 beyond Apple's standard App Analytics
- Privacy nutrition label: Camera, Microphone, Location (While In Use → Always for background)

---

## 9. Competitive Analysis Summary

| App | Rating | Key Weakness |
|---|---|---|
| Nexar | 4.6 | Requires account, cloud-focused, privacy concerns |
| Sentry Dash Cam | 3.8 | Overheating issues, poor background support |
| CamOn | 3.2 | Crashes frequently, no incident detection |
| DailyRoads Voyager | 3.5 | Android-first, iOS version neglected |

**Our differentiation:** Thermal management as a first-class feature, reliable background recording, no account required, privacy-first (local storage only).

---

## 10. Revenue Model (Recommendation)

- **Free tier:** Full recording with 2GB storage cap, 720p only
- **Pro (one-time $9.99 or $2.99/month):** Unlimited storage cap, 1080p/4K, incident detection, all cameras
- Implemented via StoreKit 2
- No ads — ever. Dashcam users need a clean, distraction-free UI.

---

## 11. Approval & Sign-off

| Role | Name | Status |
|---|---|---|
| Product Owner | Justin | ✅ Draft Approved |
| Lead Engineer | (Claude Code) | ⏳ Pending |
| QA Lead | (Manual/Automated) | ⏳ Pending |
