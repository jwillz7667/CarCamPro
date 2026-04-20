# Contributing to CarCam Pro

> **This is a proprietary, closed-source project.** External contributions
> are not accepted at this time. These guidelines apply to authorized
> collaborators (employees, contractors, reviewers) only.

---

## ▎ Before you start

1. Read [`CLAUDE.md`](./CLAUDE.md) for the project's engineering conventions.
2. Read [`README.md § Development Workflow`](./README.md#-development-workflow)
   for the concurrency model, naming rules, and logging expectations.
3. Confirm you have access to the repository and a valid Apple Developer
   provisioning profile.

## ▎ Branching model

- `main` — always shippable. Protected branch. Requires PR + CODEOWNERS review + green CI.
- `feature/<short-slug>` — new features, one ticket per branch.
- `fix/<short-slug>` — bug fixes.
- `chore/<short-slug>` — dependency bumps, tooling, docs.
- `hotfix/<short-slug>` — emergency production fixes; merged directly into `main`
  and back-ported to any active release branch.

Branch names are kebab-case. Keep them under 40 characters.

## ▎ Commits

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

<body — optional, wrap at 72 cols>

<footer — optional; e.g. "Refs #123", "BREAKING CHANGE: …">
```

Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `build`, `ci`.

Examples:

```
feat(thermal): apply 60s recovery delay before tier upshift
fix(recording): prevent segment rotation from dropping audio buffers
refactor(live-hud): extract GForceTarget into its own file
```

Commits should be small, self-contained, and pass tests on their own (allows
safe `git bisect`).

## ▎ Pull requests

### Before opening

- [ ] All new code has tests or a written justification for why not.
- [ ] `xcodebuild test` passes locally on `iPhone 16 Pro` simulator.
- [ ] SwiftLint + SwiftFormat run clean (if configured in CI).
- [ ] No new `print()` statements. All logging goes through `AppLogger`.
- [ ] No new third-party dependencies added without explicit sign-off.
- [ ] Screenshots / screen recordings attached for UI changes.
- [ ] `docs/` updated if you've changed architecture or public contracts.

### PR template

Use [`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md).
Keep the description focused on **why**, not **what** — the diff explains
what changed.

### Review

- All PRs require at least **one approval** from a CODEOWNER.
- Address every review comment (resolve, reply, or push a fixup).
- Prefer **rebase + merge** over **merge commits** to keep history linear.
- Squash only when the branch has commits that were purely WIP.

## ▎ Code style

### Swift

- Swift 6 strict concurrency — no `@unchecked Sendable` without justification.
- `async/await` over completion handlers. `actor` over locks.
- Prefer value types (`struct`, `enum`). Classes only when reference semantics
  or framework integration requires.
- `guard` for early returns; `if let` for optional binding.
- Booleans named as questions: `isLoading`, `hasLocked`, `shouldRotate`.
- `enum` error types conforming to `LocalizedError`.
- Extensions grouped by protocol conformance.

### SwiftUI

- `@Observable` for view models; `@State` for view-local state only.
- No business logic in view bodies — extract helpers or view models.
- No force-unwraps (`!`). No `as!`. No `try!` outside test code.
- Every new screen gets a preview (see `#Preview {}`) when feasible.

### Comments

- Default to **no comments**. Well-named identifiers do the job.
- Write a comment only when the *why* is non-obvious (hidden constraint,
  subtle invariant, workaround, surprising behavior).
- Never comment *what* the code does.

## ▎ Testing

- Unit tests live in `CarCam ProTests/`, mirroring the `CarCam Pro/`
  directory structure.
- Test one behavior per test method. Use `given_when_then` naming where it
  helps.
- Mock at the protocol boundary (e.g. `CameraServiceProtocol`), not via
  runtime swizzling.
- UI tests are opt-in per feature and should exercise the golden path only.

## ▎ Release process

1. Open a `chore/release-vX.Y.Z` branch.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
3. Update `CHANGELOG.md`.
4. Open a PR titled `chore(release): vX.Y.Z`.
5. Once merged, tag `vX.Y.Z` on `main` and push.
6. Archive and upload to App Store Connect via Xcode or fastlane.

## ▎ Questions

Ping the maintainer (see [`CODEOWNERS`](./CODEOWNERS)). For security issues,
see [`SECURITY.md`](./SECURITY.md).
