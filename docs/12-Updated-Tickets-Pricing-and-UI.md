# Updated Implementation Tickets — Pricing & UI Revisions
## DashCam Pro

**Date:** April 12, 2026
**Purpose:** These tickets REPLACE the corresponding sections in Document 08. Feed these to Claude Code instead of the original tickets for the affected areas.

---

## TICKET 12-REVISED: Settings, Paywall & Tiered Subscriptions

**This replaces original Ticket 12.**

```
In the DashCamPro project, build the full settings screen and the
3-tier subscription system (Free / Pro / Premium).

IMPORTANT: The minimum deployment target is now iOS 26.0 to fully
leverage Liquid Glass APIs. Update the project settings.

=== STOREKIT 2 SUBSCRIPTION SETUP ===

Create Features/Paywall/StoreKitManager.swift:
- StoreKit 2 implementation with 4 subscription products
- Product IDs:
    com.dashcampro.pro.monthly      → $4.99/month
    com.dashcampro.pro.yearly       → $39.99/year
    com.dashcampro.premium.monthly  → $9.99/month
    com.dashcampro.premium.yearly   → $79.99/year
- Subscription Group: "DashCam Pro Subscriptions"
  Premium is higher tier than Pro (upgrade path supported)
- Load products, handle purchases, verify entitlements
- Check entitlement status via Transaction.currentEntitlements
- Restore purchases support
- 7-day free trial for Pro plans (introductory offer)
- Handle upgrade (Pro → Premium) and downgrade (Premium → Pro) at renewal
- Grace period handling (16 days for billing retry)

Create a SubscriptionTier enum:
```swift
enum SubscriptionTier: Comparable {
    case free
    case pro
    case premium
}
```

Create a SubscriptionManager (an @Observable class) that exposes:
- currentTier: SubscriptionTier (computed from active entitlements)
- isPro: Bool (tier >= .pro)
- isPremium: Bool (tier == .premium)
- Listen to Transaction.updates for real-time status changes

=== FEATURE GATING ===

Free tier limits (enforce across all services):
- Max resolution: 720p only
- Max frame rate: 24fps
- Storage cap: locked to 2 GB (setting disabled)
- Segment duration: locked to 3 minutes
- Camera: back wide only (other options show lock icon)
- Background recording: DISABLED (recording stops on background)
- Incident detection: DISABLED
- GPS/speed metadata: NOT recorded
- Audio recording: DISABLED
- Auto-start: DISABLED
- Live Activity: NOT shown

Pro tier unlocks:
- Resolution up to 1080p
- 30fps
- Storage cap up to 10 GB
- All segment durations (1/3/5/10 min)
- All cameras
- Background recording
- Incident detection (30s buffer before/after)
- GPS/speed metadata
- Audio recording
- Auto-start
- Live Activity

Premium tier unlocks everything in Pro, PLUS:
- 4K resolution
- Unlimited storage cap (or custom amount)
- Extended incident buffer (60s before/after)
- Family sharing support (up to 5 devices)

When a user taps a gated feature, present the PaywallView as a sheet.
Show a small tier badge next to gated options:
- "PRO" badge: blue capsule with .system(size: 9, weight: .bold)
- "PREMIUM" badge: purple capsule with .system(size: 9, weight: .bold)

=== PAYWALL SCREEN ===

Create Features/Paywall/PaywallView.swift using full Liquid Glass design:

- Dark background (#0A0A0A)
- App icon with glass circle backing at top:
  .glassEffect(.regular.tint(.red.opacity(0.3)), in: .circle)
- "Unlock DashCam Pro" title, "Choose your plan" subtitle
- Plan cards inside a GlassEffectContainer:
  - Pro Yearly: "MOST POPULAR" badge, blue tint glass
    "$39.99/year (saves 33%)" with "$3.33/mo" subtitle
    ".glassEffect(.regular.tint(.blue.opacity(0.3)).interactive())"
  - Premium Yearly: "BEST VALUE" badge, purple tint glass
    "$79.99/year (saves 33%)" with "$6.67/mo" subtitle
    ".glassEffect(.regular.tint(.purple.opacity(0.3)).interactive())"
  - Expandable "Monthly Plans" section with:
    Pro Monthly ($4.99/mo) and Premium Monthly ($9.99/mo)
- Selected plan has brighter tint; use glassEffectID + namespace
  for morphing selection animation with withAnimation(.bouncy)
- Feature comparison grid showing Free vs Pro vs Premium
  (use checkmarks and X marks)
- Large CTA button: "Start Free Trial" for Pro, "Subscribe" for Premium
  Glass capsule with colored tint matching selected tier
  .glassEffect(.regular.tint(tierColor).interactive(), in: .capsule)
- "Restore Purchases" link below CTA
- Terms + Privacy links (REQUIRED by Apple)
- Auto-renewal disclosure text (REQUIRED by Apple):
  "Subscriptions auto-renew unless cancelled at least 24 hours
   before the end of the current period."

=== SETTINGS SCREEN ===

Update Features/Settings/SettingsView.swift:
- Use standard SwiftUI Form (gets Liquid Glass styling in iOS 26 automatically)
- Sections: Recording, Segments, Incident Detection, Power Management,
  Behavior, Subscription, About
- Gated options show tier badges and trigger paywall on tap when locked
- Subscription section shows current tier + "Manage" button → PaywallView
- About section:
  - Version (triple-tap for dev stats)
  - Privacy Policy, Terms of Use (Link views)
  - Contact Support (mailto:)
  - Restore Purchases button
- All settings persist via @AppStorage
- Settings changes take effect immediately on active recording

Create a StoreKit configuration file (.storekit) for testing in
Xcode with all 4 products defined for Sandbox testing.
```

---

## TICKET 13-REVISED: Full iOS 26 Liquid Glass Polish Pass

**This replaces original Ticket 13.**

```
In the DashCamPro project, do a COMPLETE iOS 26 Liquid Glass polish pass.
The app must look like it was designed by Apple for iOS 26.

IMPORTANT: Target iOS 26.0. Use these APIs extensively:
- .glassEffect() with .regular, .clear, and tinting
- .glassEffect(.regular.interactive()) on ALL buttons
- GlassEffectContainer for grouped glass elements
- glassEffectID + @Namespace for morphing transitions
- .tabBarMinimizeBehavior(.onScrollDown)
- .tabViewBottomAccessory for mini recording status
- .contentTransition(.numericText()) on all changing numbers
- .sensoryFeedback() for haptics

=== RECORDING SCREEN ===

Full camera preview edge-to-edge as the background.
ALL UI elements float above as Liquid Glass:

Status bar overlay (top of screen):
- HStack inside .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
- Line 1: Red pulsing dot + "REC" + monospaced timer + resolution label
- Line 2: Thermal state dot (colored) + label + storage used/cap
- Timer uses .contentTransition(.numericText()) for rolling digits
- Padded 16pt from edges

Record button (bottom center):
- 72pt glass circle
- When idle: red filled circle inside glass
  .glassEffect(.regular.interactive(), in: .circle)
- When recording: white rounded square (stop icon) inside red-tinted glass
  .glassEffect(.regular.tint(.red.opacity(0.4)).interactive(), in: .circle)
- Subtle scale pulse animation when recording (1.0 → 1.05, 1.5s loop)
- .sensoryFeedback(.start/.stop, trigger: isRecording)

Tool buttons (left and right of record button):
- Inside a GlassEffectContainer
- Mic toggle: 48pt glass circle, mic.fill / mic.slash.fill
- Camera flip: 48pt glass circle, camera.rotate.fill
- Both: .glassEffect(.regular.interactive(), in: .circle)
- Camera flip: rotation3DEffect transition when switching

Incident alert:
- Yellow border flash (2x over 1 second)
- "⚠ INCIDENT SAVED" floating badge — yellow background, capsule shape
- Enters with .transition(.move(edge: .top).combined(with: .opacity))
- Heavy haptic feedback
- Auto-dismisses after 3 seconds

=== LIBRARY SCREEN ===

Dark background (#0A0A0A).

Filter chips at top:
- Inside GlassEffectContainer(spacing: 8)
- Each filter: .glassEffect with capsule shape
- Selected filter: .tint(.blue.opacity(0.4))
- Unselected: plain .regular

Clip thumbnails:
- 2-column LazyVGrid, 8pt spacing
- Each: rounded rectangle clip shape (cornerRadius: 12)
- Bottom info strip: glass overlay with time + duration
  .glassEffect(.regular, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
- Protected badge: top-left glass pill with yellow tint
  "SAVED" text + shield.checkered icon
  .glassEffect(.regular.tint(.yellow.opacity(0.3)), in: .capsule)
- Async thumbnail loading with placeholder shimmer animation

Storage bar footer:
- Sticky at bottom above tab bar
- Glass panel with drive icon + progress bar + usage text
- .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
- Progress bar color: green < 70%, yellow 70-90%, red > 90%

Tab bar: .tabBarMinimizeBehavior(.onScrollDown) — collapses on scroll.

Empty state:
- Large video.slash icon in glass circle
- "No recordings yet" title
- "Start recording to see your clips here" subtitle

=== CLIP DETAIL SCREEN ===

Video player full-width with rounded corners.
Glass scrub bar overlaid on bottom of video:
  .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
Metadata card below: glass panel with date, duration, size, speed, incident info
  .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
Action buttons in GlassEffectContainer:
  Protect (yellow tint), Star (orange tint), Share (blue tint), Delete (red tint)
  Each: .glassEffect(.regular.tint(color.opacity(0.3)).interactive())

=== SETTINGS SCREEN ===

Standard SwiftUI Form (inherits iOS 26 glass styling automatically).
Ensure dark color scheme is set.
Pro/Premium badges use capsule backgrounds with appropriate colors.

=== ONBOARDING SCREENS ===

Each screen:
- Dark background, centered layout
- Large SF Symbol in glass circle:
  .glassEffect(.regular.tint(tintColor.opacity(0.3)), in: .circle)
- Title: .system(size: 28, weight: .bold, design: .rounded)
- Description: .body, .white.opacity(0.7), center-aligned
- CTA button: full-width glass capsule with colored tint
  .glassEffect(.regular.tint(color.opacity(0.4)).interactive(), in: .capsule)
- Page dots at bottom

Screen icons and tints:
1. Welcome: video.circle.fill, red tint
2. Camera: camera.fill, blue tint
3. Microphone: mic.fill, green tint
4. Location: location.fill, purple tint
5. Legal: doc.text.fill, orange tint
6. Ready: checkmark.circle.fill, green tint

=== TAB BAR ===

Use the new Tab API (NOT deprecated tabItem):
```swift
TabView {
    Tab("Record", systemImage: "video.circle.fill") { RecordingView() }
    Tab("Library", systemImage: "film.stack.fill") { LibraryView() }
    Tab("Settings", systemImage: "gearshape.fill") { SettingsView() }
}
```

Add .tabViewBottomAccessory for mini recording indicator:
When recording is active on non-Record tabs, show a small glass pill
with red dot + "Recording · 00:14:32" so the user knows it's still going.

=== GLOBAL ===

- .preferredColorScheme(.dark) on the root view
- ALL backgrounds: Color(hex: "0A0A0A")
- ALL text: .white or .white.opacity() for hierarchy
- ALL fonts: SF Pro system fonts (.system(...)) — no custom fonts
- ALL interactive glass elements: .interactive() for press feedback
- ALL changing numbers: .contentTransition(.numericText())
- ALL haptics: .sensoryFeedback() declarative API where possible
- Minimum touch target: 44pt (glass buttons should be 48pt+)

Verify the complete flow works end-to-end with glass styling:
1. Fresh install → glass onboarding → permissions → glass recording screen
2. Record → see glass status bar with live timer → glass record button
3. Switch to Library tab → glass filter chips → glass thumbnail cards
4. Tap clip → glass detail view → glass action buttons
5. Settings → native iOS 26 glass Form → paywall with glass plan cards
6. Background recording → glass Live Activity → glass tab bar accessory
```

---

## TICKET S0-REVISED: Project Setup Update

**Add this to the BEGINNING of Ticket 1.**

```
CRITICAL: Set minimum deployment target to iOS 26.0 (not iOS 16).
This is required to use Liquid Glass APIs:
- .glassEffect() modifier
- GlassEffectContainer
- .glassEffectID()
- .tabBarMinimizeBehavior()
- .tabViewBottomAccessory()
- New Tab API in TabView
- .contentTransition(.numericText())
- .sensoryFeedback() declarative haptics

The Tab API replaces the deprecated .tabItem() modifier.
Use Tab("Label", systemImage: "icon") { Content() } syntax.
```

---

## NEW TICKET 16: Conversion Triggers & Upsell System

```
In the DashCamPro project, implement smart conversion triggers that
naturally guide Free users to Pro, and Pro users to Premium.

Create Shared/Utilities/ConversionTriggerManager.swift:
- Tracks user behavior to trigger paywall at the right moments
- Uses @AppStorage to persist trigger counts

Free → Pro triggers (show PaywallView with Pro highlighted):

1. Background block trigger:
   When user backgrounds the app during recording:
   - Recording stops (Free limitation)
   - On return, show a glass alert:
     "Recording stopped when you switched apps."
     "Upgrade to Pro for background recording."
     [Continue Free] [Upgrade to Pro]
   - Alert styled with .glassEffect

2. Camera lock trigger:
   When user taps a locked camera option in settings or recording:
   - Show paywall with "All cameras available with Pro"

3. Incident miss trigger:
   After 5th recording session, show a subtle glass banner:
   "Pro automatically saves footage when it detects incidents."
   Dismissable, shown once.

4. Session milestone trigger:
   After 5 successful recording sessions:
   - Show friendly glass prompt:
     "You've recorded 5 drives with DashCam Pro!"
     "Ready to unlock the full experience?"
     [Not Now] [See Pro Plans]
   - Only shown once. Tracked in @AppStorage.

Pro → Premium upsell triggers:

1. Storage cap trigger:
   When Pro user hits 10 GB cap:
   - Glass banner: "Storage full. Premium gives you unlimited storage."
   - Show paywall with Premium highlighted

2. 4K request trigger:
   When Pro user taps 4K in resolution picker:
   - Show paywall with Premium highlighted
   - "4K recording available with Premium"

3. Power user trigger:
   After 14 consecutive days of recording:
   - Glass notification: "You're a power user!"
   - "Premium is built for drivers like you."
   - Show once, dismissable.

Implementation:
- All triggers respect a cooldown: no paywall shown more than
  once per 48 hours (tracked via last-shown timestamp)
- All trigger banners use Liquid Glass styling
- .glassEffect(.regular.tint(.blue.opacity(0.3))) for Pro triggers
- .glassEffect(.regular.tint(.purple.opacity(0.3))) for Premium triggers
- Banners animate in with .transition(.move(edge: .top).combined(with: .opacity))
- Include "Don't show again" option that permanently suppresses
  that specific trigger
```
