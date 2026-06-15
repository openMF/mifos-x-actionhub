# v2 — reusable workflows for the consolidated KMP release ladder

This directory is the **v2 surface** of `openMF/mifos-x-actionhub`. It introduces:

- A uniform **promotion ladder** (Stage 0 firebase → Stage 1 internal → Stage 2 beta → Stage 3 production) across all platforms
- **Approval gates** via GHA environments (consumer-configured)
- **Supersede semantics** (`concurrency.cancel-in-progress: true`) — new release cancels pending approvals of the previous
- **Auto-tag + auto-release** cadences (weekly, monthly)
- **NEW capabilities** not in v1: rollback, security scanning, deployment status dashboard, release notes generation

Calls into the consolidated platform repos at `@v2.0.0`:

- `openMF/mifos-x-actionhub-publish-android-kmp@v2.0.0`
- `openMF/mifos-x-actionhub-publish-apple-kmp@v2.0.0` (iOS + macOS)
- `openMF/mifos-x-actionhub-publish-desktop-kmp@v2.0.0` (Windows + Linux)
- `openMF/mifos-x-actionhub-publish-web-kmp@v2.0.0`

## Why a v2/ subdirectory

The 10 existing workflows at `.github/workflows/*.yaml` are **UNCHANGED**. Community consumers pinned at `@v1.0.16` continue working without any migration. v2 is purely additive — consumers opt-in by referencing files under this subdir.

## File index

### Release ladder (5 files)

| File | Purpose | Pattern |
|------|---------|---------|
| [`release-multi-platform.yaml`](./release-multi-platform.yaml) | Fan-out across all 4 platforms in parallel | Pick which platforms via `include_*` toggles |
| [`release-android.yaml`](./release-android.yaml) | Android ladder (Firebase / Play Internal / Beta / Production) | Thin wrapper → `publish-android-kmp@v2.0.0` |
| [`release-apple.yaml`](./release-apple.yaml) | iOS + macOS ladder | `platform: ios \| mac` input |
| [`release-desktop.yaml`](./release-desktop.yaml) | Windows + Linux ladder | `target: windows-exe \| msi-signed \| microsoft-store \| linux-deb` |
| [`release-web.yaml`](./release-web.yaml) | Web ladder (preview / staging / production) | `host: gh-pages \| cloudflare-pages \| netlify \| vercel` |

### Auto-tag + auto-release (2 files)

| File | Cadence | Default starting rung |
|------|---------|----------------------|
| [`tag-weekly-release.yaml`](./tag-weekly-release.yaml) | Sunday 04:00 UTC | `beta` (Stage 2) |
| [`tag-monthly-release.yaml`](./tag-monthly-release.yaml) | 1st of month 03:30 UTC | `production` (Stage 3) |

Cron triggers live in the **CONSUMER's** workflow file; v2 provides the reusable implementation.

### Quality + observability (5 files)

| File | Purpose |
|------|---------|
| [`pr-check.yaml`](./pr-check.yaml) | Multi-platform PR validation with `platforms:` input filter (replaces v1's split between `pr-check.yaml` + `pr-check-android.yaml`) |
| [`quality-gate.yaml`](./quality-gate.yaml) | Combined: Kover coverage + Spotless + Detekt + Dependency Guard + SBOM |
| [`security-scan.yaml`](./security-scan.yaml) | CycloneDX SBOM + OSV vuln scan + gitleaks secret scan |
| [`deployment-status.yaml`](./deployment-status.yaml) | Reads consumer's `deployment/PROMOTION_LOG.yaml` → renders Markdown rung-matrix dashboard as workflow step summary |
| [`release-notes-generate.yaml`](./release-notes-generate.yaml) | Auto-generate Markdown release notes from conventional commits since last tag |

### Recovery (1 file)

| File | Purpose |
|------|---------|
| [`rollback.yaml`](./rollback.yaml) | Revert a release per platform (Play track demote, TestFlight expire, Mac App Store remove, GH Release retract) |

## Consumer usage pattern

```yaml
# consumer/.github/workflows/release-android.yml
name: Release Android
on:
  workflow_dispatch:
    inputs:
      version_tag:  { required: true, type: string }
      starting_rung:
        type: choice
        options: [firebase, internal, beta, production]
        default: firebase

jobs:
  release:
    uses: openMF/mifos-x-actionhub/.github/workflows/v2/release-android.yaml@v1.0.17
    with:
      android_package_name: cmp-android
      version_tag:          ${{ inputs.version_tag }}
      starting_rung:        ${{ inputs.starting_rung }}
    secrets: inherit
```

## What stayed at top level (UNCHANGED)

- `multi-platform-build-and-publish.yaml`, `promote-to-production.yaml`, `android-build-and-publish.yaml`, `build-and-deploy-site.yaml` — v1 release surface
- `pr-check.yaml`, `pr-check-android.yaml`, `test-coverage.yaml` — v1 PR validation
- `cache-cleanup.yaml`, `cache-management.yml`, `monthly-version-tag.yaml` — maintenance (private-org cache hygiene; mifos-pay@v1.0.11 dependency)

## Migration path for existing v1 consumers

| Currently on | Path forward |
|---|---|
| `@v1.0.16` calling `multi-platform-build-and-publish.yaml` | Migrate to `@v1.0.17` calling `v2/release-multi-platform.yaml`. New inputs structure; ~30 min. |
| `@v1.0.16` calling `pr-check.yaml` + `pr-check-android.yaml` | Replace both with `@v1.0.17` `v2/pr-check.yaml` + `platforms:` input. |
| `@v1.0.11` calling `monthly-version-tag.yaml` (mifos-pay) | Optional upgrade to `v2/tag-monthly-release.yaml` for ladder integration. Old workflow keeps working. |

## Versioning

- `@v1.0.17+` — includes this v2/ subdir alongside v1 files
- `@v1.0.16` and earlier — v1 surface only, unchanged forever
- Future `@v2.0.0` of this repo would be the breaking-change cutover (deprecating v1 surface entirely). Not yet scoped.
