#!/bin/bash
# Native XCTest UI audits of the separate synthetic app. Never installs or modifies security settings.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT_APP="${SMART_CLIPBOARD_AUDIT_APP:-$REPO/dist/Smart Clipboard Audit.app}"
RESULTS="${SMART_CLIPBOARD_AUDIT_RESULTS:-${TMPDIR:-/tmp}/smart-clipboard-accessibility-results/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
DERIVED_DATA="$REPO/.build/accessibility-ui-runner"
AUDIT_ARCH="$(uname -m)"
BUILD_ONLY=false
ONLY_TESTING=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-only) BUILD_ONLY=true; shift ;;
        --app) AUDIT_APP="$2"; shift 2 ;;
        --results) RESULTS="$2"; shift 2 ;;
        --only-testing) ONLY_TESTING="$2"; shift 2 ;;
        --help)
            echo 'Usage: scripts/test-accessibility.sh [--build-only] [--app PATH] [--results DIRECTORY] [--only-testing AccessibilityAuditTests/TEST]'
            echo 'Running without --build-only launches native UI in the separate synthetic audit app.'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
mkdir -p "$RESULTS"
RESULTS="$(cd "$RESULTS" && pwd)"
xcodebuild -version > "$RESULTS/toolchain.txt"
/usr/bin/sw_vers > "$RESULTS/macos.txt"
set +e
xcodebuild build-for-testing \
    -project "$REPO/Tests/AccessibilityUITests/AccessibilityAudit.xcodeproj" \
    -scheme AccessibilityAudit -configuration Debug -destination "platform=macOS,arch=$AUDIT_ARCH" \
    -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    2>&1 | tee "$RESULTS/build.log"
build_status=${PIPESTATUS[0]}
set -e
if [[ "$build_status" -ne 0 ]]; then exit "$build_status"; fi
if [[ "$BUILD_ONLY" == true ]]; then
    echo "Runner built without launching UI. Build log: $RESULTS/build.log"
    exit 0
fi

test_runs=("$DERIVED_DATA"/Build/Products/*.xctestrun)
if [[ ${#test_runs[@]} -ne 1 || ! -f "${test_runs[0]}" ]]; then
    echo 'Expected one generated .xctestrun file; inspect the runner build output.' >&2
    exit 1
fi
xcrun python3 "$REPO/Tests/AccessibilityUITests/prepare-test-run.py" \
    "${test_runs[0]}" "$AUDIT_APP" "$RESULTS/Audit.xctestrun"
test_args=(-xctestrun "$RESULTS/Audit.xctestrun" -destination "platform=macOS,arch=$AUDIT_ARCH"
    -parallel-testing-enabled NO -resultBundlePath "$RESULTS/AccessibilityAudit.xcresult")
if [[ -n "$ONLY_TESTING" ]]; then test_args+=("-only-testing:AccessibilityAuditTests/$ONLY_TESTING"); fi
set +e
xcodebuild test-without-building "${test_args[@]}" 2>&1 | tee "$RESULTS/test.log"
test_status=${PIPESTATUS[0]}
set -e

# Export even when tests fail, and preserve the original failing exit status.
export_status=0
if [[ -d "$RESULTS/AccessibilityAudit.xcresult" ]]; then
    xcrun xcresulttool get test-results summary --path "$RESULTS/AccessibilityAudit.xcresult" > "$RESULTS/summary.json" || export_status=1
    xcrun xcresulttool get test-results tests --path "$RESULTS/AccessibilityAudit.xcresult" > "$RESULTS/tests.json" || export_status=1
    xcrun xcresulttool export attachments --path "$RESULTS/AccessibilityAudit.xcresult" --output-path "$RESULTS/attachments" || export_status=1
else
    echo 'Xcode did not produce a result bundle; the audit is incomplete.' >&2
    export_status=1
fi
echo "Native accessibility audit evidence: $RESULTS"
if [[ "$test_status" -ne 0 ]]; then exit "$test_status"; fi
if [[ "$export_status" -ne 0 ]]; then exit "$export_status"; fi
# A successful xcodebuild/export alone does not prove any selected test ran.
xcrun python3 "$REPO/Tests/AccessibilityUITests/verify-test-results.py" \
    "$RESULTS/summary.json" "$RESULTS/tests.json" --only-testing "$ONLY_TESTING"
