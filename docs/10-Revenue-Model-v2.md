# Revenue Model v2 — Tiered Pricing Strategy
## DashCam Pro

**Version:** 2.0 (replaces Section 10 of PRD)
**Date:** April 12, 2026

---

## 1. Pricing Philosophy

No ads — ever. A dashcam is a safety tool. We monetize through genuine value tiers, not dark patterns. Each tier unlocks meaningfully different capabilities. The free tier is generous enough to hook users but limited enough that serious drivers upgrade within their first week.

---

## 2. Tier Breakdown

### FREE TIER — "Starter"
**Price:** $0

What's included:
- 720p recording at 24fps
- 2 GB storage cap
- 3-minute segment loops
- Basic clip library and playback
- Manual start/stop only
- Single camera (back wide only)
- Thermal management (always on — we never let anyone's phone overheat)

What's NOT included:
- No incident detection
- No background recording (recording stops when app goes to background)
- No GPS/speed metadata
- No audio recording
- No custom segment durations
- Subtle "Upgrade to Pro" banner in library (non-intrusive, dismissable)

**Purpose:** Let users try the core recording experience. The moment they switch to Maps and recording stops, they understand why Pro exists.

---

### PRO TIER — "Pro"
**Price:** $4.99/month or $39.99/year (save 33%)

Everything in Free, plus:
- 1080p recording at 30fps
- 10 GB storage cap
- Background recording (keep recording while using other apps)
- Incident detection (accelerometer-based, configurable sensitivity)
- GPS/speed metadata on every clip
- Audio recording
- Configurable segment duration (1/3/5/10 min)
- All cameras (back wide, ultrawide, front cabin cam)
- Auto-start recording on app launch
- Live Activity in Dynamic Island
- Priority thermal management (smarter throttling keeps quality higher longer)
- Protected clips (incident auto-save)

**Purpose:** The tier 90% of paying users will choose. Covers every feature a daily commuter or weekend driver needs.

---

### PREMIUM TIER — "Premium"
**Price:** $9.99/month or $79.99/year (save 33%)

Everything in Pro, plus:
- 4K recording capability
- Unlimited storage cap (limited only by device storage)
- Custom storage cap (any amount)
- Extended incident buffer (60 seconds before + after, vs 30 in Pro)
- Speed/GPS overlay burned into video (v1.1 feature, included at launch for Premium)
- Early access to new features (beta channel)
- Priority support (direct email response within 24 hours)
- Cloud backup integration when available (v1.1)
- Dual camera recording when available (v1.2)
- Family sharing (up to 5 devices on one subscription)

**Purpose:** For rideshare drivers, fleet operators, and power users who depend on the app daily. The unlimited storage and 4K make this essential for professionals.

---

## 3. Pricing Comparison Table

| Feature | Free | Pro ($4.99/mo) | Premium ($9.99/mo) |
|---|---|---|---|
| Max Resolution | 720p | 1080p | 4K |
| Max Frame Rate | 24fps | 30fps | 30fps |
| Storage Cap | 2 GB | 10 GB | Unlimited |
| Background Recording | No | Yes | Yes |
| Incident Detection | No | Yes | Yes |
| Incident Buffer | — | 30s before/after | 60s before/after |
| GPS/Speed Metadata | No | Yes | Yes |
| Audio Recording | No | Yes | Yes |
| Camera Options | Back wide only | All cameras | All cameras |
| Segment Durations | 3 min only | 1/3/5/10 min | 1/3/5/10 min + custom |
| Auto-start | No | Yes | Yes |
| Live Activity | No | Yes | Yes |
| Speed Overlay on Video | No | No | Yes |
| Cloud Backup (v1.1) | No | No | Yes |
| Family Sharing | No | No | Yes (5 devices) |
| Support | Community/FAQ | Standard email | Priority (24hr) |

---

## 4. Conversion Strategy

**Free → Pro conversion triggers:**
- User backgrounds the app and recording stops → "Upgrade to Pro for background recording"
- User experiences an event that would have triggered incident detection → "Pro would have auto-saved this moment"
- User wants to switch cameras → "All cameras available with Pro"
- After 5 recording sessions → gentle prompt: "You've recorded 5 drives. Ready to unlock the full dashcam?"

**Pro → Premium upsell triggers:**
- User hits 10 GB storage cap → "Need more space? Premium gives you unlimited storage"
- User records frequently (daily for 2+ weeks) → "You're a power user. Premium is built for you."
- When 4K or overlay features launch → feature announcement with Premium badge

**Trial strategy:**
- 7-day free trial of Pro for all new users (starts after onboarding)
- No trial for Premium (users should experience Pro first, then decide to upgrade)

---

## 5. StoreKit 2 Product Configuration

```
Product IDs:
  com.dashcampro.pro.monthly        → $4.99/month  (auto-renewable)
  com.dashcampro.pro.yearly          → $39.99/year  (auto-renewable)
  com.dashcampro.premium.monthly     → $9.99/month  (auto-renewable)
  com.dashcampro.premium.yearly      → $79.99/year  (auto-renewable)

Subscription Group: "DashCam Pro Subscriptions"
  - Premium is a higher tier than Pro (upgrade path)
  - Downgrade from Premium → Pro takes effect at renewal
  - Cancel → reverts to Free at end of billing period

Introductory Offers:
  - Pro Monthly: 7-day free trial (one per Apple ID)
  - Pro Yearly: 7-day free trial
  - Premium: No trial (must have been Pro subscriber first, or pay directly)

Grace Period: 16 days (App Store default for subscription billing retry)
```

---

## 6. Future Revenue Stream — DashCam Pro Store

### Phase 1 (v1.1–v1.2): Digital Goods
- **Recording themes:** Custom UI color themes (cyberpunk neon, minimal white, racing red)
- **Overlay packs:** Speed/GPS overlay styles (minimal, HUD-style, vintage timestamp)
- Price: $0.99–$2.99 each as non-consumable IAP

### Phase 2 (v2.0): Physical Goods — Accessories Store
In-app store section linking to a Shopify/web store for physical products:

- **DashCam Pro Phone Mount** — Custom-designed car mount optimized for dashcam positioning
  - Adjustable angle for windshield dashcam view
  - Built-in airflow channel for thermal management (the mount has ventilation slots behind the phone)
  - MagSafe compatible
  - Integrated cable management for charging while recording
  - Price: $29.99–$39.99
  - *This is a massive differentiator — no other dashcam app sells a companion mount*

- **DashCam Pro Charging Cable** — Extra-long (6ft) braided USB-C cable designed for dashboard routing
  - Price: $14.99

- **DashCam Pro Bundle** — Mount + Cable + 1 year Premium subscription
  - Price: $69.99 (saves ~$25)

### Store Implementation:
- In-app "Store" tab (added in v2.0, replaces nothing — becomes 4th tab)
- Physical goods: link out to web store (Apple doesn't allow physical goods via IAP)
- Digital goods: StoreKit 2 non-consumable purchases
- Affiliate/referral program for driving instructors and fleet managers

---

## 7. Revenue Projections (Conservative)

| Metric | Month 1 | Month 6 | Month 12 |
|---|---|---|---|
| Downloads | 2,000 | 8,000 | 20,000 |
| Free → Pro conversion | 8% | 10% | 12% |
| Pro → Premium conversion | 15% of Pro | 20% of Pro | 25% of Pro |
| Monthly Pro subscribers | 160 | 800 | 2,400 |
| Monthly Premium subscribers | 24 | 160 | 600 |
| Monthly recurring revenue | ~$1,040 | ~$5,600 | ~$17,960 |
| Physical store revenue | — | — | ~$3,000/mo |

*Based on typical utility app conversion rates. Dashcam apps with good reviews tend to over-index on conversion because the use case is "safety" — people pay for peace of mind.*

---

## 8. Paywall Design Requirements

The paywall must be beautiful, not sleazy. Design principles:

- Show all three tiers side-by-side with clear feature comparison
- Highlight "Most Popular" on Pro yearly
- Highlight "Best Value" on Premium yearly
- Show the per-month savings on yearly plans
- "Start Free Trial" as the primary CTA for Pro
- Restore Purchases link (required by Apple)
- Terms of Use + Privacy Policy links (required by Apple)
- Subscription auto-renewal disclosure (required by Apple)
- No fake urgency, no countdown timers, no "limited time" language
