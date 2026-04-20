<!-- Thank you for contributing to CarCam Pro.
     Fill in the sections below. Delete any that don't apply. -->

## ▎ Summary

<!-- 1–3 sentences. Why this change exists, not what the diff does. -->

## ▎ Linked issue / ticket

Closes #

## ▎ Type of change

- [ ] `feat` — new user-facing functionality
- [ ] `fix` — bug fix
- [ ] `perf` — performance improvement
- [ ] `refactor` — internal restructuring, no behavior change
- [ ] `test` — adds / fixes tests
- [ ] `docs` — documentation only
- [ ] `chore` — tooling, deps, CI, release bookkeeping
- [ ] `BREAKING CHANGE` — requires coordinated deployment or data migration

## ▎ Screenshots / screen recording

<!-- REQUIRED for any UI change. Drag an image or .mov file here.
     Before/after preferred. -->

| Before | After |
|:--:|:--:|
| — | — |

## ▎ Test plan

- [ ] `xcodebuild test` passes locally on `iPhone 16 Pro` simulator
- [ ] Manually verified the golden path on device (iPhone model: ___)
- [ ] New tests added to cover behavior introduced in this PR
- [ ] Edge cases tested: <!-- list them -->

## ▎ Thermal / battery impact

<!-- For changes that touch the recording pipeline, camera, or incident
     detection. Delete this section otherwise. -->

- [ ] No impact (pure UI, no new background work)
- [ ] Profiled with Instruments — attach screenshot
- [ ] Tested thermal tier transitions in simulator (`Features > Thermal State`)

## ▎ Checklist

- [ ] I read and followed [`CONTRIBUTING.md`](../CONTRIBUTING.md)
- [ ] Code builds cleanly with **no new warnings**
- [ ] No `print()` — all logging goes through `AppLogger`
- [ ] No new third-party dependencies
- [ ] `CHANGELOG.md` updated (under `[Unreleased]`)
- [ ] Docs updated if architecture / public contracts changed
- [ ] PR title follows Conventional Commits (e.g. `feat(thermal): …`)
