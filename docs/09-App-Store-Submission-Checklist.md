# App Store Submission Checklist
## DashCam Pro

**Version:** 1.0
**Date:** April 12, 2026

---

## Pre-Submission Checklist

### Code & Build

- [ ] App builds in Release configuration with zero warnings
- [ ] All unit tests pass (80%+ coverage on Core/)
- [ ] All UI tests pass
- [ ] No memory leaks (Instruments Leaks, 1-hour recording session)
- [ ] No crashes in 10 consecutive recording sessions across 3 devices
- [ ] Swift strict concurrency: Complete (no warnings)
- [ ] Minimum deployment target: iOS 16.0
- [ ] Archive builds successfully
- [ ] App size is reasonable (< 30 MB without recordings)

### Functionality

- [ ] Camera preview loads within 2 seconds of app launch
- [ ] Recording starts within 500ms of button tap
- [ ] Segment rotation works with zero dropped frames
- [ ] Background recording survives for 1+ hour while using Maps
- [ ] Recording resumes after phone call interruption
- [ ] Incident detection fires correctly at all sensitivity levels
- [ ] False positive rate < 10% during normal driving
- [ ] Thermal management prevents shutdown in 1-hour session
- [ ] FIFO storage cap enforcement works correctly
- [ ] Protected clips survive FIFO deletion
- [ ] Clip playback works for all recorded clips
- [ ] Share sheet works for clips
- [ ] All settings persist between app launches
- [ ] Settings changes take effect immediately
- [ ] In-app purchases complete successfully (Sandbox)
- [ ] Restore purchases works
- [ ] Free tier limits are properly enforced

### Permissions

- [ ] Camera permission: request + handle denial gracefully
- [ ] Microphone permission: request + handle denial + app works without it
- [ ] Location permission: request "Always" + handle "When In Use" fallback + handle denial
- [ ] All permission denial states show helpful messages with "Open Settings" button
- [ ] App works (recording only, no GPS) if location is denied

### UI/UX

- [ ] Dark theme consistent across all screens
- [ ] All text readable (sufficient contrast ratio)
- [ ] All touch targets ≥ 44pt
- [ ] Haptic feedback works on: record start/stop, incident, settings changes
- [ ] Animations are smooth (60fps, no jank)
- [ ] Supports Dynamic Type (test at accessibility XXL)
- [ ] VoiceOver can navigate all screens
- [ ] VoiceOver announces recording state changes
- [ ] No hardcoded strings (all in Localizable.xcstrings even if English-only for now)
- [ ] Works in portrait orientation (landscape is acceptable on iPad)
- [ ] App switcher snapshot does not show camera feed (privacy)

### App Store Connect Configuration

- [ ] Bundle ID registered in Apple Developer Portal
- [ ] App ID created in App Store Connect
- [ ] App name: "DashCam Pro"
- [ ] Subtitle: "Your Phone. Your Dashcam."
- [ ] Primary category: Navigation
- [ ] Secondary category: Utilities
- [ ] Content rating questionnaire completed (likely 4+)
- [ ] Pricing: Free (with IAP)
- [ ] In-App Purchases configured: Pro Monthly ($2.99), Pro Lifetime ($9.99)
- [ ] IAP review information submitted
- [ ] Availability: All territories (or select territories)

### App Store Metadata

- [ ] App description written (compelling, highlights differentiators)
- [ ] Keywords optimized (dashcam, dash cam, car camera, driving recorder, etc.)
- [ ] What's New text: "Initial release of DashCam Pro"
- [ ] Support URL configured
- [ ] Marketing URL (optional, can be app website)
- [ ] Privacy Policy URL (REQUIRED — host on a simple website)

### Screenshots

Required sizes (at minimum):
- [ ] 6.9" (iPhone 16 Pro Max) — 1320 x 2868 or 2868 x 1320
- [ ] 6.7" (iPhone 15 Plus/Pro Max) — 1290 x 2796
- [ ] 6.5" (iPhone 11 Pro Max) — 1242 x 2688
- [ ] 5.5" (iPhone 8 Plus) — 1242 x 2208

Screenshot content (3-5 screenshots per size):
- [ ] Screenshot 1: Recording screen with live camera preview and status overlay
- [ ] Screenshot 2: Library view with clip grid
- [ ] Screenshot 3: Incident detection alert (yellow flash overlay)
- [ ] Screenshot 4: Settings screen
- [ ] Screenshot 5: "Works in background" illustration (split screen concept)

### App Review Notes

```
This app functions as a dashboard camera for vehicles. It requires
background audio and location capabilities for the following legitimate
reasons:

BACKGROUND AUDIO: The AVCaptureSession requires an active audio session
to continue recording video when the app is not in the foreground. Users
need to use navigation and music apps while recording.

BACKGROUND LOCATION: GPS coordinates and vehicle speed are logged with
each recording clip for evidence purposes. Location updates also help
maintain the background execution state necessary for continuous recording.

The app does not require user login or an account. All data is stored
locally on the device. No data is transmitted to external servers.

To test: simply launch the app, grant permissions, and tap the record
button. Switch to another app (like Maps) and return — recording will
have continued in the background.
```

### Privacy

- [ ] Privacy Manifest (PrivacyInfo.xcprivacy) included
- [ ] Privacy nutrition labels configured in App Store Connect:
  - Data Linked to You: None
  - Data Not Linked to You: None
  - Data Used to Track You: None
  - Data types: Precise Location (App Functionality), Photos or Videos (App Functionality)
- [ ] No third-party analytics SDKs
- [ ] No advertising SDKs
- [ ] No tracking of any kind

### Legal

- [ ] Privacy Policy hosted at accessible URL
- [ ] Terms of Use hosted at accessible URL
- [ ] In-app legal disclaimer about recording laws (in onboarding)
- [ ] EULA configured (or using Apple's standard EULA)

---

## Common Rejection Reasons to Avoid

**Guideline 2.5.4 — Background Modes:** Apple rejects apps that declare background modes but don't obviously need them. Our App Review notes must clearly explain why audio and location background modes are essential. The app must actually use these modes (not just declare them).

**Guideline 5.1.1 — Data Collection:** If we ever add analytics, we need to disclose it. For v1.0 with zero data collection, we're clean.

**Guideline 3.1.2 — Subscriptions:** IAP subscriptions must clearly describe what the user gets, offer a free trial or free tier, and include links to terms and privacy policy on the paywall screen.

**Guideline 4.0 — Design:** App must not look unfinished. All screens must be polished, no placeholder text, no debug UI visible in release builds.

**Guideline 2.1 — Crashes:** Apple test on their devices. If the app crashes during their testing, it's an instant rejection. Our testing matrix must cover the devices Apple commonly uses (latest iPhone + one older model).

---

## Post-Submission

- [ ] Monitor App Store Connect for review status
- [ ] Respond to any reviewer questions within 24 hours
- [ ] If rejected: read the specific guideline cited, fix the issue, resubmit
- [ ] Once approved: verify the live listing looks correct
- [ ] Download from App Store and do a final smoke test on a clean device
- [ ] Set up App Store Connect notifications for crash reports
- [ ] Monitor ratings/reviews daily for the first 2 weeks
