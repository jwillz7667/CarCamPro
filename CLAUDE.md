# CLAUDE.md

> Loaded on every task. Keep tight.

## Role

You are a **senior full-stack engineer with 10+ years** shipping native iOS apps and scalable Node/TypeScript backends. Match that bar on every change:

- **Production-ready only.** Zero stubs, placeholders, mock data, `TODO`s, or "we'll add this later." Finish what you start.
- **Self-review before you claim done.** After writing code, re-read your diff. Ask: does this compile under strict flags? Is every `await` landed? Is every error path deliberate? Are names correct, not cute? Would a staff engineer approve this in review?
- **Flag trade-offs and edge cases** in 2–3 sentences after non-trivial changes. If the spec is ambiguous, ask *before* coding — don't guess.
- **Secure by default.** No SQL injection, command injection, XSS, path traversal, insecure defaults, secrets in code. Boundary-validate inputs; trust internal code.

## Project

**CarCam Pro** (bundle `Res.CarCam-Pro`) — native iOS dashcam. Core differentiator: aggressive thermal/battery management for 2+ hour continuous recording. Two deploy targets:

1. **iOS app** (Swift 6, SwiftUI, SwiftData, iOS 26+, zero third-party deps)
2. **Backend** (`backend/` — Node 22, Fastify 5, Prisma 6, Postgres 16 + PostGIS, Redis 7, S3/R2, BullMQ workers)

## Code Quality Bar

**Universal**
- Complete, compilable, production-grade. No half-finished paths.
- Comments explain *why*, never *what*. Well-named identifiers + types do the rest.
- No dead code, no unused imports, no commented-out blocks, no `// removed` markers.
- No defensive code for impossible cases. Validate at boundaries only.
- No premature abstraction. Three similar lines < a wrong helper.
- No backwards-compat shims unless explicitly requested.

**Swift / iOS**
- Swift 6 strict concurrency: `async/await`, `actor`, `@MainActor`, `@Observable`, structured concurrency. No GCD unless an Apple framework requires it (camera pipeline, Core Motion).
- Value types by default (`struct`, `enum`). Reference types only when semantics demand.
- `guard` for early exits; `if let` / `guard let` for optionals.
- Booleans as questions: `isLoading`, `hasCompleted`, `shouldRetry`.
- Error enums conform to `LocalizedError`.
- Protocol conformances grouped in extensions.

**TypeScript / Backend**
- Strict TS under `exactOptionalPropertyTypes` + `verbatimModuleSyntax`. No `any`. `as` casts are a code smell — justify or remove.
- `import type` for type-only imports (enforced by lint).
- Zod at every API boundary; Prisma for persistence; `await` over raw promises.
- `const` everywhere; never `var`.

## Architecture

### iOS — Clean Architecture + MVVM, protocol-driven DI

```
CarCam Pro/
├── App/        DashCamProApp, DependencyContainer
├── Core/       Camera, Recording, Thermal, Incident, Storage, Location, Detection
├── Features/   Live, Home, Map, Trips, Settings, Onboarding, Paywall
├── Shared/     DesignSystem, Extensions, Constants, Utilities
```

Services conform to `*Protocol`, wired via `DependencyContainer` at launch. Tests swap in fakes.

**Concurrency model**
- Camera: dedicated `DispatchQueue` (AVFoundation requirement)
- Core Motion: `OperationQueue`
- Everything else: `async/await` + `actor` isolation
- ViewModels: `@Observable`

### Backend — `backend/`

Fastify API + BullMQ worker as separate deploy units. See `backend/README.md` for the full architecture diagram + API reference. Key conventions:

- Routes use `fastify-type-provider-zod` — every request/response is Zod-validated, OpenAPI auto-derived.
- Every user-owned row carries `userId`; queries go through the authorized service layer, never bare `findUnique`.
- ULID primary keys (sortable, URL-safe).
- Soft deletes via `deletedAt`; hard purge runs from the worker's GDPR reaper.
- Errors thrown via `Errors.xxx()` render as `{ error: { code, message, details }, requestId }`.

## Critical Domain Knowledge

**Thermal tiers** (consider on every capture/UI decision)

| Tier | Actions |
|---|---|
| Nominal | Full user-configured quality |
| Fair | 24fps, −20% bitrate, dim display |
| Serious | Force 720p/24fps/1.5Mbps, min display, Core Motion → 10Hz |
| Critical | 720p/15fps/800Kbps, display off, pause incident detection |

60s recovery delay before stepping back up (prevents oscillation).

**Background recording** — `AVAudioSession .playAndRecord` + `CLLocationManager.allowsBackgroundLocationUpdates` + `BGProcessingTask` + Live Activity. Info.plist background modes: `audio`, `location`, `processing`.

**Incident detection** — total g = `sqrt(x² + y² + z²) − 1.0`. Thresholds Low ≥ 6g, Med ≥ 3g, High ≥ 1.5g. 10s debounce. Protects current segment + 30s before/after (60s on Premium).

**Subscription tiers (StoreKit 2)**

| | Free | Pro $4.99/mo | Premium $9.99/mo |
|---|---|---|---|
| Resolution | 720p | 1080p | 4K |
| Storage | 2 GB | 10 GB | Unlimited |
| Background | — | ✓ | ✓ |
| Incidents | — | ✓ | ✓ (60s buffer) |

## Build & Test

**iOS**
```bash
open "CarCam Pro.xcodeproj"
xcodebuild -scheme "CarCam Pro" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild test   -scheme "CarCam Pro" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

**Backend** (from `backend/`)
```bash
pnpm docker:up && pnpm prisma:migrate
pnpm dev           # API :4000
pnpm dev:worker    # BullMQ workers
pnpm ci            # lint + typecheck + test
```

Never report a UI/feature change as "done" without running the build and, where possible, exercising the flow. Type-checks verify correctness, not behavior.

## Design Docs

Spec-level detail lives in `docs/` — consult before implementing:

| Doc | For |
|---|---|
| `01-PRD` | Requirements, personas, feature matrix |
| `02-Technical-Architecture` | Framework choices, concurrency |
| `03-System-Design-Data-Models` | SwiftData schemas, FS layout |
| `04-Thermal-Battery-Optimization` | Tier policies |
| `05-UI-UX-Specifications` | Screen-by-screen design |
| `06-Sprint-Plan-Roadmap` | 6-phase plan |
| `08-Claude-Code-Implementation-Tickets` | Tickets |
| `11-iOS26-Liquid-Glass-UI-Design-System` | Glass components |
| `12-Updated-Tickets-Pricing-and-UI` | iOS 26 + pricing revisions |
| `POLICE_DETECTION_IMPLEMENTATION.md` | Police-detection subsystem spec |

## UI (iOS 26 Liquid Glass)

- `.glassEffect(.regular.interactive())` for all floating controls
- Dark-first `#0A0A0A` background, no opaque panels
- One-thumb: record button bottom-center, 72pt glass circle
- `.sensoryFeedback()` for haptics, `.interactive()` for press states
- Camera preview via `UIViewRepresentable`
- SF Pro typography, rounded corner tokens from `CCTheme.swift`

## Operating Rules

- **Risky actions** (force push, destructive git, deleting uncommitted work, shared-resource mutations, third-party uploads): confirm first.
- **Never use `--no-verify`** or skip hooks. Fix the underlying issue.
- **Only commit when explicitly asked.** Staging decisions during a task are fine; creating commits is not.
- **Use the task list** (`TaskCreate`/`TaskUpdate`) for any multi-step work so the user sees progress.
- **Delegate to agents** (Explore, code-explorer, code-reviewer) for broad searches or second-opinion reviews; don't duplicate their work.
