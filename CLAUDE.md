# CLAUDE.md — mifos-x-actionhub (Tier 2 — Orchestrator)

> **You are in the ORCHESTRATOR repo.** Before editing anything, read
> [`CONTRIBUTING.md`](CONTRIBUTING.md) — it tells you whether the change
> belongs HERE or in a publish-* repo.

## The 3-tier chain

```
Consumer (kmp-project-template + forks)        Tier 1 — thin wrapper
    └─ uses @v1.0.X →
mifos-x-actionhub (THIS REPO)                  Tier 2 — orchestrator
    └─ uses @v2.0.X →
mifos-x-actionhub-publish-{android,apple,      Tier 3 — per-platform
                          desktop,web}-kmp           ladders
```

## What lives here

| Concern | File | Owns |
|---|---|---|
| Multi-platform fan-out | `.github/workflows/release-multi-platform-v2.yaml` | workflow_dispatch inputs, per-platform jobs, version-resolve, cross-platform UX |
| Secret naming convention | [`V2_GUIDE.md`](.github/V2_GUIDE.md) | Canonical lowercase snake_case schema for all platforms |
| Decision guide | [`CONTRIBUTING.md`](CONTRIBUTING.md) | "Which repo do I edit?" — read this FIRST |
| Sibling repo registry | [`PLATFORM_REGISTRY.yaml`](PLATFORM_REGISTRY.yaml) | What each publish-* repo handles |

## "Where do I make this change?"

> Full table is in [`CONTRIBUTING.md`](CONTRIBUTING.md). Quick lookup:

**Edit HERE (orchestrator) when…**
- Adding/removing a workflow_dispatch input
- Changing how `version_tag` auto-computes (YYYY.M.D logic)
- Changing default rungs per platform
- Adding a new platform (also create new publish-* repo)
- Updating secret naming docs in V2_GUIDE.md

**Edit a publish-* repo when…**
- Changing a rung's build/sign/upload logic
- Adding a new GitHub Environment
- Adding/changing target-specific secrets
- Changing Xcode version, runner image, Fastlane lanes
- Adding `validate-secrets` checks

**After editing here:**
1. Tag `v1.0.{X+1}` on `main`
2. Bump consumer wrappers (`release-multi-platform.yml`) `@v1.0.X` → `@v1.0.{X+1}`

## Versioning

| Bump | When |
|---|---|
| Patch (`v1.0.21` → `v1.0.22`) | ref bumps, docs, minor input tweaks |
| Minor (`v1.0.X` → `v1.1.0`) | new platform added |
| Major (never, inside v1) | reserved for breaking changes |

## Don't

- ❌ Don't pin to floating tags like `@v1` — every reference is immutable patch tag
- ❌ Don't edit `validate-secrets` env lists here — they live in each publish-* repo
- ❌ Don't change rung logic here — it lives in each publish-* repo's `release.yaml`
- ❌ Don't add platform-specific secret docs here without also updating `V2_GUIDE.md`

## Always

- ✅ Read [`CONTRIBUTING.md`](CONTRIBUTING.md) BEFORE editing anything
- ✅ Read [`V2_GUIDE.md`](.github/V2_GUIDE.md) for canonical secret schema
- ✅ Bump every `@v2.0.X` ref together when fanning out a coordinated change
- ✅ Tag immediately after merge (orchestrator's value is its tag)
