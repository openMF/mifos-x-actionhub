# Contributing — where to make changes

This document answers **one question**: when you want to change the release
pipeline, which repo do you edit?

The mifos-x-actionhub ecosystem is a **3-tier reusable-workflow chain**:

```
┌──────────────────────────────────────────────────────────────────────┐
│  TIER 1 — Consumer repo (e.g. kmp-project-template, your fork)       │
│  .github/workflows/release-multi-platform.yml                        │
│  → Thin wrapper. Calls orchestrator with consumer-specific inputs.   │
└──────────────────────────────────────────────────────────────────────┘
                              │ uses: @v1.0.X
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  TIER 2 — Orchestrator (this repo, openMF/mifos-x-actionhub)         │
│  .github/workflows/release-multi-platform-v2.yaml                    │
│  → Fans out to per-platform workflows. Owns the multi-platform UX.   │
└──────────────────────────────────────────────────────────────────────┘
                              │ uses: @v2.0.X
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  TIER 3 — Per-platform publish-* repos (4 repos)                     │
│  mifos-x-actionhub-publish-{android,apple,desktop,web}-kmp           │
│  .github/workflows/release.yaml                                      │
│  → The actual rungs: build, sign, upload, promote per environment.   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Decision tree

> **Rule of thumb**: if your change touches **what runs** (signing, upload,
> environment names, secret schema), edit the publish-* repo. If your change
> touches **what shows up in the workflow_dispatch form** or **how platforms
> fan out**, edit this repo (the orchestrator).

### ✅ Edit a publish-* repo when…

| Change | Repo |
|---|---|
| Add/remove a rung (e.g. add a `staging` rung between internal and beta) | the platform's publish-* repo |
| Change the signing flow (e.g. switch Android from V1 → V2 signing) | `publish-android-kmp` |
| Add a new code-signing secret (e.g. Azure cert profile) | the platform's publish-* repo + this repo's `V2_GUIDE.md` (secret table) |
| Change GitHub Environment names (e.g. `android-firebase` → `android-fad`) | the platform's publish-* repo |
| Add a new web host (e.g. Vercel preview deploy URL extraction) | `publish-web-kmp` |
| Add a new desktop target (e.g. `linux-snap`, `windows-portable-exe`) | `publish-desktop-kmp` |
| Add per-rung `validate-secrets` preflight checks | the platform's publish-* repo |
| Change the macOS Xcode version, iOS runner image | the platform's publish-* repo |
| Update Fastlane plugin versions / lane logic | the platform's publish-* repo |
| Add a new step inside an existing job (e.g. notarization, slack notify) | the platform's publish-* repo |

After landing the change: **tag a new patch** in the publish-* repo, then bump
the `@vX.X.X` reference for that platform in this repo's
`release-multi-platform-v2.yaml`.

### ✅ Edit THIS repo (orchestrator) when…

| Change | File |
|---|---|
| Add a new platform (e.g. tvOS, embedded Linux) | `release-multi-platform-v2.yaml` + new publish-* repo |
| Change the workflow_dispatch input schema (add/remove a rung dropdown) | `release-multi-platform-v2.yaml` |
| Change how `version_tag` is auto-computed (YYYY.M.D logic) | `release-multi-platform-v2.yaml` (the `version-resolve` job) |
| Change the default rung per platform (e.g. iOS default `firebase` → `internal`) | `release-multi-platform-v2.yaml` |
| Add cross-platform validation (e.g. Android + iOS both need same version_tag) | `release-multi-platform-v2.yaml` |
| Update the global secret naming convention | `V2_GUIDE.md` + every publish-* repo's `validate-secrets` env list |
| Bump composite-action versions used by publish-* (e.g. `actions/checkout@v4` → `@v5`) | the publish-* repo first, then bump ref here |
| Change which job emits which `run-name` emoji | each publish-* repo's `run-name:` line |
| Add documentation about secret naming, environment setup, fork bootstrap | `V2_GUIDE.md` or `CONTRIBUTING.md` (this file) |

After landing the change: **tag a new patch on this repo** (e.g. `v1.0.22`),
then bump the `@v1.0.X` reference in every consumer's
`release-multi-platform.yml`.

### ✅ Edit BOTH when…

| Change | What to do |
|---|---|
| Renaming a secret (e.g. `firebase_creds` → `firebase_app_distribution_creds`) | Update `validate-secrets` env in publish-* (tag patch), then update `V2_GUIDE.md` and any sync-secrets script in this repo (tag patch) |
| Adding a new rung that needs new orchestrator input (e.g. `android_rung: hotfix`) | Add rung to publish-android-kmp (`if:` conditions), tag patch, then add `hotfix` to the orchestrator's `android_rung` choice list and pass it through |
| Adding a new platform end-to-end | Create new publish-* repo, tag v2.0.0, then add platform fan-out job + workflow_dispatch input + version-resolve wiring in this repo |
| Changing what `secrets: inherit` propagates | Both sides — publish-* declares the `secrets:` block, orchestrator declares the same, consumer uses `inherit` |

---

## Versioning policy

| Repo | Tag format | Bump rules |
|---|---|---|
| Consumer | n/a (always references a fixed orchestrator tag) | Bump `@v1.0.X` in `release-multi-platform.yml` when adopting new orchestrator features |
| Orchestrator (this repo) | `v1.0.X` | **patch** for ref bumps / docs / minor input tweaks; **minor** for new platform; never breaking inside `v1` |
| publish-* | `v2.0.X` | **patch** for any change inside the ladder; **minor** for new rung; **major** for breaking secret rename or rung removal |

**Floating tags** (`@v1`, `@v2`) are NOT used by the orchestrator or consumer
wrapper — every reference is pinned to an immutable patch tag. The single
`@v2` floating tag in some publish-* repos is a leftover for backward compat
and should be ignored when wiring fresh.

---

## End-to-end change flow (worked examples)

### Example 1: "Add per-rung validate-secrets preflight to publish-apple-kmp"

This is what was done in `v2.0.5` of all 4 publish-* repos.

1. Edit `publish-apple-kmp/.github/workflows/release.yaml`:
   - Add `run-name: "🍎 Release ${{ inputs.platform }} ..."` under `name:`
   - Add new `validate-secrets:` job at top of `jobs:`
   - Add `needs: [validate-secrets]` to `stage-0-firebase`
   - Add `needs: [validate-secrets, stage-0-firebase]` to `stage-1-testflight-internal`
2. PR → merge → tag `v2.0.5`
3. **This repo** — edit `release-multi-platform-v2.yaml`: change every
   `publish-apple-kmp/.github/workflows/release.yaml@v2.0.0` to `@v2.0.5`
4. PR → merge → tag `v1.0.22`
5. **Consumer repo** — edit `release-multi-platform.yml`: change
   `openMF/mifos-x-actionhub/.github/workflows/release-multi-platform-v2.yaml@v1.0.21`
   to `@v1.0.22`
6. PR → merge

### Example 2: "Add a new workflow_dispatch input for staged-rollout %"

This is what was done when `production_rollout` was added.

1. **This repo only** — edit `release-multi-platform-v2.yaml`:
   - Add `production_rollout` to `workflow_dispatch.inputs`
   - Pass it to the android fan-out job's `with:` block
2. publish-android-kmp **already accepts** `production_rollout` — no change
   needed there
3. PR → merge → tag `v1.0.21`
4. Consumer wrapper adds the new input passthrough → bump to `@v1.0.21`

### Example 3: "Switch Android upload key to a new keystore"

1. **publish-android-kmp only** — no change. The `validate-secrets` job
   checks the secret *exists*; the actual keystore swap is a secret rotation,
   not a workflow change.
2. Consumer rotates the `upload_keystore` secret value via
   `scripts/sync-secrets-to-github.sh`. No PR. No tag bump.

### Example 4: "Add a new platform (e.g. tvOS)"

1. Create new repo `mifos-x-actionhub-publish-tvos-kmp` modeled on apple-kmp
2. Tag `v2.0.0`
3. **This repo** — add new fan-out job + workflow_dispatch input
   (`tvos_rung`) + pass to consumer
4. Tag `v1.1.0` (minor — new platform)
5. Consumer wrapper adds `tvos_rung` input → bump to `@v1.1.0`

---

## Sync-dirs propagation

Consumer forks receive `release-multi-platform.yml` updates **automatically**
via the weekly sync-dirs.yaml cron — they don't need to manually pull every
new orchestrator patch. The sync-dirs config in this repo lists which paths
get propagated to consumer template forks.

If a consumer is **not** subscribed to sync-dirs (e.g. an OSS fork that
diverged), they bump the `@v1.0.X` reference manually.

---

## Where to ask questions

- **Workflow not firing as expected?** Check this repo's
  `release-multi-platform-v2.yaml` first — the `if:` conditions on each
  fan-out job decide whether a platform runs.
- **Secret reported missing in CI?** The error came from the publish-* repo's
  `validate-secrets` preflight. Check `V2_GUIDE.md` in this repo for the
  canonical secret name, then set it via your consumer repo's
  `scripts/sync-secrets-to-github.sh` or directly via `gh secret set`.
- **"Approve and deploy" button missing in the workflow graph?** GitHub
  Environment is not configured for the rung. See `V2_GUIDE.md` §
  "Environment setup".

---

## TL;DR

```
What you want to change          → Edit which repo?
──────────────────────────────────────────────────────────────────
A rung's build/sign/upload logic → publish-{platform}-kmp
A new GitHub Environment name    → publish-{platform}-kmp
A new secret per platform        → publish-{platform}-kmp + V2_GUIDE.md
A workflow_dispatch input        → this repo (orchestrator)
The auto-version_tag computation → this repo (orchestrator)
A new platform end-to-end        → both (new publish-* + orchestrator wiring)
A consumer-only customization    → consumer's release-multi-platform.yml
Secret rotation (value only)     → no workflow change, just rotate secret
```

When in doubt: **the publish-* repos own "how the release happens"; this repo
owns "which releases happen and how they're triggered"**.
