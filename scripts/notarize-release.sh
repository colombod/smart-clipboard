#!/bin/bash
# Secrets belong in a notarytool Keychain profile, never in this script or argv.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "Error: $*" >&2; exit 1; }
RESUME=false
case "${1:-}" in
    "") [[ $# == 0 ]] || fail "Usage: $0 [--resume]" ;;
    --resume) [[ $# == 1 ]] || fail "Usage: $0 [--resume]"; RESUME=true ;;
    *) fail "Usage: $0 [--resume]" ;;
esac
[[ -n "${SIGNING_IDENTITY:-}" ]] || fail "Set SIGNING_IDENTITY to a valid Developer ID Application certificate name or SHA-1 fingerprint."
[[ -n "${NOTARY_PROFILE:-}" ]] || fail "Set NOTARY_PROFILE to an existing notarytool Keychain profile."
NOTARY_WAIT_TIMEOUT="${NOTARY_TIMEOUT:-5m}"
[[ "$NOTARY_WAIT_TIMEOUT" =~ ^[1-9][0-9]*[smh]$ ]] || fail "NOTARY_TIMEOUT must be a positive duration such as 60s or 5m."

# find-identity reports public certificate metadata only. Only its valid list is accepted.
IDENTITIES="$(security find-identity -v -p codesigning)" || fail "Could not enumerate valid code-signing identities."
IDENTITY_SHA=""
IDENTITY_NAME=""
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+\"(Developer[[:space:]]ID[[:space:]]Application:[^\"]+)\" ]]; then
        candidate_sha="${BASH_REMATCH[1]}"
        candidate_name="${BASH_REMATCH[2]}"
        if [[ "$SIGNING_IDENTITY" == "$candidate_name" || "$(printf '%s' "$SIGNING_IDENTITY" | tr '[:lower:]' '[:upper:]')" == "$candidate_sha" ]]; then
            [[ -z "$IDENTITY_SHA" ]] || fail "The certificate name is ambiguous; use its SHA-1 fingerprint."
            IDENTITY_SHA="$candidate_sha"
            IDENTITY_NAME="$candidate_name"
        fi
    fi
done <<< "$IDENTITIES"
[[ -n "$IDENTITY_SHA" ]] || fail "SIGNING_IDENTITY is not a valid Developer ID Application identity with its private key and trusted certificate chain."
[[ "$IDENTITY_NAME" =~ \(([A-Z0-9]+)\)$ ]] || fail "Could not determine the signing Team ID."
TEAM_ID="${BASH_REMATCH[1]}"
export SIGNING_IDENTITY="$IDENTITY_SHA"

APP="$PWD/dist/Smart Clipboard.app"
STATE="$PWD/dist/notarization-release"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/smart-clipboard-release.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

json_field() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
file_hash() { shasum -a 256 "$1" | awk '{print $1}'; }
verify_identity() {
    local target="$1" actual_sha
    codesign --verify --deep --strict --verbose=2 "$target"
    rm -f "$SCRATCH/certificate-"*
    # codesign treats this optional argument as a target unless attached with '='.
    codesign --display --extract-certificates="$SCRATCH/certificate-" "$target"
    [[ -f "$SCRATCH/certificate-0" ]] || fail "Could not extract the public signing certificate from $target."
    actual_sha="$(shasum -a 1 "$SCRATCH/certificate-0" | awk '{print toupper($1)}')"
    [[ "$actual_sha" == "$IDENTITY_SHA" ]] || fail "Artifact is signed with a different certificate: $target"
}
app_hash() {
    # The executable includes its signature. Stapling adds a ticket outside it.
    file_hash "$APP/Contents/MacOS/SmartClipboard"
}
verify_app() {
    local metadata helper framework="$APP/Contents/Frameworks/Sparkle.framework"
    verify_identity "$APP"
    for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
        verify_identity "$framework/Versions/B/$helper"
    done
    verify_identity "$framework"
    metadata="$(codesign --display --verbose=4 "$APP" 2>&1)"
    [[ "$metadata" == *"Identifier=com.smartclipboard.app"* ]] || fail "Unexpected app bundle identifier."
    [[ "$metadata" == *"TeamIdentifier=$TEAM_ID"* ]] || fail "Unexpected app signing team."
    [[ "$metadata" == *"(runtime)"* ]] || fail "Hardened runtime is missing."
    [[ "$metadata" == *"Timestamp="* ]] || fail "Secure signing timestamp is missing."
}
verify_unchanged_app() {
    verify_app
    [[ "$(app_hash)" == "$(cat "$STATE/app.sha256")" ]] || fail "The app changed during this release. Keep the original build when resuming."
}
notarize() {
    local stage="$1" archive="$2" submission_id result_status wait_status=0
    local submission="$STATE/$1-submission.json" result="$STATE/$1-result.json"
    if [[ ! -e "$submission" ]]; then
        # Persist the response before waiting; an interrupted/ambiguous submit is never retried automatically.
        if ! xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --output-format json > "$submission"; then
            fail "Submission could not be confirmed. Inspect $submission and notarytool history before retrying; do not create a duplicate submission."
        fi
    fi
    submission_id="$(json_field "$submission" id || true)"
    [[ "$submission_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || fail "Missing submission ID in $submission. Resolve it using notarytool history; no duplicate was submitted."
    result_status="$(json_field "$result" status || true)"
    if [[ "$result_status" != Accepted ]]; then
        echo "Waiting up to $NOTARY_WAIT_TIMEOUT for $stage submission $submission_id."
        xcrun notarytool wait "$submission_id" --keychain-profile "$NOTARY_PROFILE" --timeout "$NOTARY_WAIT_TIMEOUT" --output-format json > "$result" || wait_status=$?
        result_status="$(json_field "$result" status || true)"
    fi
    if [[ "$result_status" != Accepted ]]; then
        if [[ "$result_status" == Invalid || "$result_status" == Rejected ]]; then
            if xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" "$STATE/$stage-log.json"; then
                cat "$STATE/$stage-log.json" >&2
            fi
            fail "$stage notarization was $result_status. See $STATE/$stage-log.json; no assets were approved for publication."
        fi
        fail "$stage submission $submission_id is not yet Accepted (status: ${result_status:-unknown}, wait exit: $wait_status). Keep dist unchanged and rerun SIGNING_IDENTITY and NOTARY_PROFILE with $0 --resume. The existing submission will be reused."
    fi
    echo "$stage notarization Accepted ($submission_id)."
}

if [[ "$RESUME" == true ]]; then
    [[ -f "$STATE/identity.sha1" && -f "$STATE/app.sha256" ]] || fail "There is no resumable release in $STATE."
    [[ "$(cat "$STATE/identity.sha1")" == "$IDENTITY_SHA" ]] || fail "Resume requires the certificate used to start this release."
    verify_unchanged_app
else
    if [[ -d "$STATE" ]]; then
        [[ -f "$STATE/complete" ]] || fail "A release is already pending. Use $0 --resume; its submissions will not be duplicated."
        mv "$STATE" "$STATE-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    fi
    ./scripts/build-app.sh
    verify_app
    mkdir -p "$STATE"
    printf '%s\n' "$IDENTITY_SHA" > "$STATE/identity.sha1"
    app_hash > "$STATE/app.sha256"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Invalid app version."
BASE="Smart-Clipboard-${VERSION}-macOS-${ARCH}"
DMG="$PWD/dist/$BASE.dmg"
ZIP="$PWD/dist/$BASE.zip"

if [[ ! -f "$STATE/app-stapled" ]]; then
    if [[ ! -e "$STATE/app-submission.json" ]]; then
        ditto -c -k --sequesterRsrc --keepParent "$APP" "$STATE/app-upload.zip"
    fi
    notarize app "$STATE/app-upload.zip"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    verify_unchanged_app
    touch "$STATE/app-stapled"
fi
xcrun stapler validate "$APP"

if [[ ! -f "$STATE/packaged" ]]; then
    # Never rebuild or resign the app after its accepted submission.
    ./scripts/package-release.sh --existing-build --defer-checksums
    verify_unchanged_app
    codesign --force --timestamp --sign "$IDENTITY_SHA" "$DMG"
    verify_identity "$DMG"
    file_hash "$DMG" > "$STATE/dmg-input.sha256"
    file_hash "$ZIP" > "$STATE/zip.sha256"
    touch "$STATE/packaged"
fi
[[ "$(file_hash "$ZIP")" == "$(cat "$STATE/zip.sha256")" ]] || fail "The release ZIP changed."
if [[ -f "$STATE/dmg-final.sha256" ]]; then
    [[ "$(file_hash "$DMG")" == "$(cat "$STATE/dmg-final.sha256")" ]] || fail "The stapled DMG changed."
else
    [[ "$(file_hash "$DMG")" == "$(cat "$STATE/dmg-input.sha256")" ]] || fail "The submitted DMG changed."
fi
verify_identity "$DMG"
notarize dmg "$DMG"
if [[ ! -f "$STATE/dmg-final.sha256" ]]; then
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    file_hash "$DMG" > "$STATE/dmg-final.sha256"
fi

# Verify the final downloadable payload, including the ticket inside the ZIP.
ditto -x -k "$ZIP" "$SCRATCH/unzipped"
diff -qr "$APP" "$SCRATCH/unzipped/Smart Clipboard.app"
verify_identity "$SCRATCH/unzipped/Smart Clipboard.app"
xcrun stapler validate "$SCRATCH/unzipped/Smart Clipboard.app"
verify_unchanged_app
verify_identity "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
spctl --assess --type execute --verbose=4 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
(cd dist && shasum -a 256 "$BASE.dmg" "$BASE.zip" > "$STATE/SHA256SUMS.txt")
cp "$STATE/SHA256SUMS.txt" "$PWD/dist/SHA256SUMS.txt"
touch "$STATE/complete"
echo "Verified signed and notarized release: $DMG and $ZIP"
echo "Final checksums: $PWD/dist/SHA256SUMS.txt"
