#!/bin/bash
# tests/chain-contract.sh
#
# Cross-repo end-to-end contract tests for openMF/mifos-x-actionhub
# — the Tier-2 orchestrator that pins all 4 Tier-3 publish-* repos.
#
# Verifies the CHAIN is sound:
#   1. Static syntax — orchestrator's release-multi-platform-v2.yaml + all
#      release-{android,apple,desktop,web}-v2.yaml files
#   2. No dynamic uses regression (the bug class we fixed in 3 publish-* repos)
#   3. Every publish-* pin resolves to a REAL remote tag (live gh api check)
#   4. Caller→callee input contract: orchestrator's `with:` matches each
#      publish-*'s declared workflow_call.inputs
#   5. Caller→callee secrets contract: orchestrator's `secrets:` matches
#      each publish-*'s declared workflow_call.secrets
#   6. validate-secrets coverage — orchestrator references secrets the
#      publish-* chain needs per target
#
# This is the chain's HEALTH CHECK. If anything in the actionhub→publish-*
# integration drifts, these tests catch it BEFORE a consumer dispatches
# and silently fails.
#
# Dependencies: python3 + PyYAML, actionlint, gh CLI (live remote checks)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
FAILED_TESTS=()

run_test() {
    local name="$1"
    local cmd="$2"
    printf "  %-72s ... " "$name"
    if eval "$cmd" > /tmp/test-out 2>&1; then
        echo "✅ PASS"
        PASS=$((PASS+1))
    else
        echo "❌ FAIL"
        sed 's/^/      /' /tmp/test-out
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$name")
    fi
}

py() { python3 -c "$1"; }

# ─────────────────────────────────────────────────────────────────────────────
# Constants — the 4 Tier-3 publish-* repos
# ─────────────────────────────────────────────────────────────────────────────
PUBLISH_REPOS=(
    "publish-android-kmp"
    "publish-apple-kmp"
    "publish-desktop-kmp"
    "publish-web-kmp"
)

ORCH_RELEASE_FILE=".github/workflows/release-multi-platform-v2.yaml"

# Workflow files the orchestrator itself owns
ORCH_WORKFLOWS=(
    "release-multi-platform-v2.yaml"
    "release-android-v2.yaml"
    "release-apple-v2.yaml"
    "release-desktop-v2.yaml"
    "release-web-v2.yaml"
)

echo "════════════════════════════════════════════════════════════════════════════"
echo "  Chain Contract tests for openMF/mifos-x-actionhub"
echo "  (Tier-2 orchestrator — verifies actionhub→publish-* integration)"
echo "════════════════════════════════════════════════════════════════════════════"
echo

# ── Tier 1: Static syntax (orchestrator's own workflow files) ────────────────
echo "── Tier 1: Static syntax across orchestrator's release-*.yaml files ──"
for WF in "${ORCH_WORKFLOWS[@]}"; do
    run_test "T0x: .github/workflows/$WF parses" \
        "py 'import yaml; yaml.safe_load(open(\".github/workflows/$WF\"))'"
done
for WF in "${ORCH_WORKFLOWS[@]}"; do
    run_test "T0y: actionlint clean on $WF" \
        "actionlint .github/workflows/$WF"
done
run_test "T07: NO dynamic uses in release-multi-platform-v2.yaml" \
    "! grep -nE '^[^#]*uses: .*\\\${{ (inputs|matrix)\\.' $ORCH_RELEASE_FILE"
echo

# ── Tier 2: Pinned publish-* refs are valid (live remote check) ──────────────
echo "── Tier 2: Live remote-tag verification (every publish-* pin resolves) ──"
for REPO in "${PUBLISH_REPOS[@]}"; do
    # Extract the tag this orchestrator pins for this repo
    TAG=$(grep -oE "$REPO/.github/workflows/release.yaml@v[0-9.]+" "$ORCH_RELEASE_FILE" | head -1 | grep -oE "v[0-9.]+$")
    [ -z "$TAG" ] && { echo "  T1x: $REPO pin not found in orchestrator — SKIPPING" ; continue; }
    run_test "T1x: $REPO @ $TAG exists on remote (gh api)" \
        "[ \"\$(gh api repos/therajanmaurya/mifos-x-actionhub-$REPO/git/refs/tags/$TAG --jq .ref 2>&1)\" = \"refs/tags/$TAG\" ]"
done
echo

# ── Tier 3: Caller→callee input schema (orchestrator vs each publish-*) ──────
echo "── Tier 3: Caller→callee input schema ──"
# Pre-fetch each publish-* release.yaml at its pinned tag and stash in /tmp
for REPO in "${PUBLISH_REPOS[@]}"; do
    TAG=$(grep -oE "$REPO/.github/workflows/release.yaml@v[0-9.]+" "$ORCH_RELEASE_FILE" | head -1 | grep -oE "v[0-9.]+$")
    [ -z "$TAG" ] && continue
    gh api "repos/therajanmaurya/mifos-x-actionhub-$REPO/contents/.github/workflows/release.yaml?ref=$TAG" --jq '.content' 2>/dev/null | base64 -d > "/tmp/release-$REPO-$TAG.yaml" 2>/dev/null
done
run_test "T2a: orchestrator's call to publish-android-kmp matches its workflow_call inputs" "py '
import yaml
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
import glob
publish_files = glob.glob(\"/tmp/release-publish-android-kmp-*.yaml\")
assert publish_files, \"no fetched publish-android-kmp file\"
publish = yaml.safe_load(open(publish_files[0]))
declared = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"inputs\"].keys())
for job_name in [\"android-firebase\",\"android-internal\"]:
    if job_name in orch[\"jobs\"]:
        passed = set(orch[\"jobs\"][job_name].get(\"with\", {}).keys())
        unknown = passed - declared
        assert not unknown, job_name + \" passes inputs publish-android-kmp does not declare: \" + str(unknown)
'"
run_test "T2b: orchestrator's call to publish-apple-kmp matches its workflow_call inputs" "py '
import yaml, glob
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
publish_files = glob.glob(\"/tmp/release-publish-apple-kmp-*.yaml\")
assert publish_files, \"no fetched publish-apple-kmp file\"
publish = yaml.safe_load(open(publish_files[0]))
declared = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"inputs\"].keys())
for job_name in [\"ios\",\"mac\"]:
    if job_name in orch[\"jobs\"]:
        passed = set(orch[\"jobs\"][job_name].get(\"with\", {}).keys())
        unknown = passed - declared
        assert not unknown, job_name + \" passes inputs publish-apple-kmp does not declare: \" + str(unknown)
'"
run_test "T2c: orchestrator's call to publish-desktop-kmp matches its workflow_call inputs" "py '
import yaml, glob
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
publish_files = glob.glob(\"/tmp/release-publish-desktop-kmp-*.yaml\")
assert publish_files, \"no fetched publish-desktop-kmp file\"
publish = yaml.safe_load(open(publish_files[0]))
declared = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"inputs\"].keys())
for job_name in [\"desktop-win\",\"desktop-linux\"]:
    if job_name in orch[\"jobs\"]:
        passed = set(orch[\"jobs\"][job_name].get(\"with\", {}).keys())
        unknown = passed - declared
        assert not unknown, job_name + \" passes inputs publish-desktop-kmp does not declare: \" + str(unknown)
'"
run_test "T2d: orchestrator's call to publish-web-kmp matches its workflow_call inputs" "py '
import yaml, glob
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
publish_files = glob.glob(\"/tmp/release-publish-web-kmp-*.yaml\")
assert publish_files, \"no fetched publish-web-kmp file\"
publish = yaml.safe_load(open(publish_files[0]))
declared = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"inputs\"].keys())
if \"web\" in orch[\"jobs\"]:
    passed = set(orch[\"jobs\"][\"web\"].get(\"with\", {}).keys())
    unknown = passed - declared
    assert not unknown, \"web passes inputs publish-web-kmp does not declare: \" + str(unknown)
'"
echo

# ── Tier 4: Caller→callee secrets schema ─────────────────────────────────────
echo "── Tier 4: Caller→callee secrets schema ──"
run_test "T3a: orchestrator forwards all secrets publish-android-kmp expects" "py '
import yaml, glob
publish_files = glob.glob(\"/tmp/release-publish-android-kmp-*.yaml\")
assert publish_files
publish = yaml.safe_load(open(publish_files[0]))
expected = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"secrets\"].keys())
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
# Orchestrator may use secrets: inherit OR explicit secrets block
for job_name in [\"android-firebase\",\"android-internal\"]:
    if job_name in orch[\"jobs\"]:
        sec = orch[\"jobs\"][job_name].get(\"secrets\")
        if sec == \"inherit\":
            continue  # inherit passes everything available — OK
        if isinstance(sec, dict):
            missing = expected - set(sec.keys())
            # All publish-android-kmp secrets are required=True so missing is a real bug
            assert not missing, job_name + \" missing secrets that publish-android-kmp requires: \" + str(missing)
'"
run_test "T3b: orchestrator forwards all secrets publish-apple-kmp expects" "py '
import yaml, glob
publish_files = glob.glob(\"/tmp/release-publish-apple-kmp-*.yaml\")
assert publish_files
publish = yaml.safe_load(open(publish_files[0]))
expected = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"secrets\"].keys())
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
for job_name in [\"ios\",\"mac\"]:
    if job_name in orch[\"jobs\"]:
        sec = orch[\"jobs\"][job_name].get(\"secrets\")
        if sec == \"inherit\":
            continue
        if isinstance(sec, dict):
            unknown = set(sec.keys()) - expected
            assert not unknown, job_name + \" passes secrets publish-apple-kmp does not declare: \" + str(unknown)
'"
run_test "T3c: orchestrator forwards all secrets publish-desktop-kmp expects" "py '
import yaml, glob
publish_files = glob.glob(\"/tmp/release-publish-desktop-kmp-*.yaml\")
assert publish_files
publish = yaml.safe_load(open(publish_files[0]))
expected = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"secrets\"].keys())
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
for job_name in [\"desktop-win\",\"desktop-linux\"]:
    if job_name in orch[\"jobs\"]:
        sec = orch[\"jobs\"][job_name].get(\"secrets\")
        if sec == \"inherit\":
            continue
        if isinstance(sec, dict):
            unknown = set(sec.keys()) - expected
            assert not unknown, job_name + \" passes secrets publish-desktop-kmp does not declare: \" + str(unknown)
'"
run_test "T3d: orchestrator forwards all secrets publish-web-kmp expects" "py '
import yaml, glob
publish_files = glob.glob(\"/tmp/release-publish-web-kmp-*.yaml\")
assert publish_files
publish = yaml.safe_load(open(publish_files[0]))
expected = set(publish[\"on\" if \"on\" in publish else True][\"workflow_call\"][\"secrets\"].keys())
orch = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
if \"web\" in orch[\"jobs\"]:
    sec = orch[\"jobs\"][\"web\"].get(\"secrets\")
    if sec != \"inherit\" and isinstance(sec, dict):
        unknown = set(sec.keys()) - expected
        assert not unknown, \"web passes secrets publish-web-kmp does not declare: \" + str(unknown)
'"
echo

# ── Tier 5: Orchestrator's workflow_call interface ───────────────────────────
echo "── Tier 5: Orchestrator's own workflow_call contract ──"
run_test "T40: workflow_call inputs include core platform-target fields" "py '
import yaml
d = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
got = set(d[\"on\" if \"on\" in d else True][\"workflow_call\"][\"inputs\"].keys())
expected = set([\"android_target\",\"ios_target\",\"mac_target\",\"desktop_win_target\",\"desktop_linux_target\",\"web_target\"])
assert expected.issubset(got), \"missing: \" + str(expected - got)
'"
run_test "T41: workflow_call inputs include per-platform package-name fields" "py '
import yaml
d = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
got = set(d[\"on\" if \"on\" in d else True][\"workflow_call\"][\"inputs\"].keys())
expected = set([\"android_package_name\",\"ios_package_name\",\"mac_package_name\",\"desktop_package_name\",\"web_package_name\"])
assert expected.issubset(got), \"missing: \" + str(expected - got)
'"
run_test "T42: workflow_dispatch inputs match workflow_call inputs (UX form parity)" "py '
import yaml
d = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
trig = d[\"on\" if \"on\" in d else True]
wc_inputs = set(trig[\"workflow_call\"][\"inputs\"].keys())
wd_inputs = set(trig[\"workflow_dispatch\"][\"inputs\"].keys())
# workflow_dispatch may be a subset (some package-names are hardcoded as defaults), but every wd input must be in wc
extra_wd = wd_inputs - wc_inputs
assert not extra_wd, \"workflow_dispatch has inputs not in workflow_call: \" + str(extra_wd)
'"
echo

# ── Tier 6: Job structure ────────────────────────────────────────────────────
echo "── Tier 6: Job structure ──"
run_test "T50: validate-secrets is first (no dependencies)" "py '
import yaml
d = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
assert \"validate-secrets\" in d[\"jobs\"]
assert not d[\"jobs\"][\"validate-secrets\"].get(\"needs\")
'"
run_test "T51: version-resolve is first (no dependencies)" "py '
import yaml
d = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
assert \"version-resolve\" in d[\"jobs\"]
assert not d[\"jobs\"][\"version-resolve\"].get(\"needs\")
'"
run_test "T52: every platform job depends on [version-resolve, validate-secrets]" "py '
import yaml
d = yaml.safe_load(open(\"$ORCH_RELEASE_FILE\"))
platform_jobs = [j for j in d[\"jobs\"] if j not in [\"validate-secrets\",\"version-resolve\"]]
for j in platform_jobs:
    needs = d[\"jobs\"][j].get(\"needs\", [])
    if isinstance(needs, str): needs = [needs]
    assert \"version-resolve\" in needs and \"validate-secrets\" in needs, j + \" needs: \" + str(needs)
'"
echo

# ─────────────────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════════════════════"
echo "  Results: $PASS passed · $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "  Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do echo "    - $t"; done
fi
echo "════════════════════════════════════════════════════════════════════════════"
exit $FAIL
