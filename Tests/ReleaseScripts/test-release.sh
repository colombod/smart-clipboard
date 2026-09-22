#!/bin/bash
# Isolated orchestration tests: all signing, Apple service, build and assessment
# commands are fakes. No credentials, real identities, network or installed app.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/smart-clipboard-release-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
printf 'public certificate fixture\n' > "$TEST_ROOT/certificate.der"
printf 'other public certificate fixture\n' > "$TEST_ROOT/other-certificate.der"
FIXTURE_SHA="$(shasum -a 1 "$TEST_ROOT/certificate.der" | awk '{print toupper($1)}')"
export TEST_ROOT FIXTURE_SHA
cat > "$TEST_ROOT/bin/fake" <<'FAKE'
#!/bin/bash
set -euo pipefail
tool="$(basename "$0")"
printf '%s' "$tool" >> "$CASE_ROOT/commands.log"
printf ' %q' "$@" >> "$CASE_ROOT/commands.log"
printf '\n' >> "$CASE_ROOT/commands.log"
case "$tool" in
    security)
        printf '  1) %s "Developer ID Application: Test Person (TEAM123456)"\n     1 valid identities found\n' "$FIXTURE_SHA"
        ;;
    swift)
        if [[ "$1" == build ]]; then
            if [[ " $* " == *' --show-bin-path '* ]]; then printf '%s\n' "$CASE_ROOT/bin-output"; exit; fi
            mkdir -p "$CASE_ROOT/bin-output"
            printf '#!/bin/sh\nexit 0\n' > "$CASE_ROOT/bin-output/SmartClipboard"
            chmod +x "$CASE_ROOT/bin-output/SmartClipboard"
            framework="$CASE_ROOT/bin-output/Sparkle.framework"
            mkdir -p "$framework/Versions/B/Resources" "$framework/Versions/B/XPCServices/Installer.xpc" "$framework/Versions/B/XPCServices/Downloader.xpc" "$framework/Versions/B/Updater.app"
            printf 'helper fixture\n' > "$framework/Versions/B/Autoupdate"
            printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>2.10.0</string></dict></plist>\n' > "$framework/Versions/B/Resources/Info.plist"
            ln -sf B "$framework/Versions/Current"
            ln -sf Versions/Current/Resources "$framework/Resources"
        else mkdir -p "$2"; fi
        ;;
    iconutil) printf 'icon fixture' > "${@: -1}" ;;
    otool) printf 'Load command 1\n          cmd LC_RPATH\n      cmdsize 48\n         path @executable_path/../Frameworks (offset 12)\n' ;;
    install_name_tool) : ;;
    codesign)
        if [[ "$1" == --verify ]]; then [[ "${MOCK_VERIFY_FAIL:-false}" != true ]]; exit; fi
        if [[ "$1" == --display ]]; then
            if [[ "${2:-}" == --extract-certificates=* ]]; then
                fixture="$TEST_ROOT/certificate.der"
                if [[ "${MOCK_CERT_MISMATCH:-false}" == true ]]; then fixture="$TEST_ROOT/other-certificate.der"; fi
                prefix="${2#--extract-certificates=}"
                cp "$fixture" "${prefix}0"
            elif [[ "${2:-}" == --extract-certificates ]]; then
                echo 'Separate optional prefix is interpreted as a signing target.' >&2
                exit 1
            else
                printf 'Identifier=com.smartclipboard.app\nTeamIdentifier=TEAM123456\nCodeDirectory flags=0x10000(runtime)\nTimestamp=Test date\n'
            fi
        fi
        ;;
    hdiutil)
        if [[ "$1" == create ]]; then printf 'DMG fixture\n' > "${@: -1}"; else [[ -f "${@: -1}" ]]; fi
        ;;
    spctl) [[ "${MOCK_ASSESS_FAIL:-false}" != true ]] ;;
    xcrun)
        if [[ "$1" == notarytool ]]; then
            case "$2" in
                submit)
                    if [[ "$3" == *app-upload.zip ]]; then stage=app; id=11111111-1111-1111-1111-111111111111
                    else stage=dmg; id=22222222-2222-2222-2222-222222222222; fi
                    [[ -f "$3" ]]
                    printf '%s\n' "$stage" >> "$CASE_ROOT/submissions.log"
                    if [[ "${MOCK_SUBMIT_FAIL:-false}" == true ]]; then exit 1; fi
                    printf '{"id":"%s","status":"In Progress"}\n' "$id"
                    ;;
                wait)
                    if [[ "$3" == 11111111-* ]]; then stage=app; else stage=dmg; fi
                    status=Accepted
                    if [[ "${MOCK_PENDING_STAGE:-}" == "$stage" ]]; then status='In Progress'; fi
                    if [[ "${MOCK_INVALID_STAGE:-}" == "$stage" ]]; then status=Invalid; fi
                    printf '{"id":"%s","status":"%s"}\n' "$3" "$status"
                    [[ "$status" == Accepted ]]
                    ;;
                log) printf '{"issues":[{"message":"Test notarization rejection"}]}\n' > "${@: -1}" ;;
                *) exit 98 ;;
            esac
        elif [[ "$1" == stapler ]]; then
            target="$3"
            if [[ "$2" == staple ]]; then
                if [[ -d "$target" ]]; then printf 'app ticket\n' > "$target/Contents/notary-ticket"
                else printf 'DMG ticket\n' >> "$target"; fi
            else
                if [[ -d "$target" ]]; then [[ -f "$target/Contents/notary-ticket" ]]
                else [[ "$(tail -n 1 "$target")" == 'DMG ticket' ]]; fi
            fi
        else exit 98; fi
        ;;
    *) exit 99 ;;
esac
FAKE
chmod +x "$TEST_ROOT/bin/fake"
for tool in security swift iconutil codesign hdiutil spctl xcrun otool install_name_tool; do ln -s fake "$TEST_ROOT/bin/$tool"; done
export PATH="$TEST_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export SIGNING_IDENTITY="$FIXTURE_SHA" NOTARY_PROFILE=fixture-profile NOTARY_TIMEOUT=1s

new_case() {
    CASE_ROOT="$TEST_ROOT/$1"; export CASE_ROOT
    mkdir -p "$CASE_ROOT/scripts" "$CASE_ROOT/Resources" "$CASE_ROOT/docs"
    cp "$REPO/scripts/build-app.sh" "$REPO/scripts/embed-sparkle.sh" "$REPO/scripts/package-release.sh" "$REPO/scripts/notarize-release.sh" "$CASE_ROOT/scripts/"
    cp "$REPO/Resources/Info.plist" "$CASE_ROOT/Resources/"
    cp "$REPO/Resources/ThirdPartyNotices.txt" "$CASE_ROOT/Resources/"
    cp "$REPO/docs/INSTALL.txt" "$CASE_ROOT/docs/"
    : > "$CASE_ROOT/commands.log"
}
run_release() { "$CASE_ROOT/scripts/notarize-release.sh" "$@" > "$CASE_ROOT/output.log" 2>&1; }
must_fail() { if "$@"; then echo "Expected failure in $CASE_ROOT" >&2; exit 1; fi; }
assert_count() {
    local actual
    actual="$(awk -v pattern="$2" '$0 ~ pattern {count++} END {print count+0}' "$1")"
    [[ "$actual" == "$3" ]] || { echo "Expected $3 matches of $2, found $actual in $1" >&2; exit 1; }
}

new_case accepted
if ! run_release; then cat "$CASE_ROOT/output.log" >&2; exit 1; fi
[[ -f "$CASE_ROOT/dist/notarization-release/complete" ]]
packaged_plist="$CASE_ROOT/dist/Smart Clipboard.app/Contents/Info.plist"
/usr/bin/plutil -lint "$packaged_plist" >/dev/null
cmp "$CASE_ROOT/Resources/Info.plist" "$packaged_plist"
[[ -n "$(/usr/libexec/PlistBuddy -c 'Print :NSLocalNetworkUsageDescription' "$packaged_plist")" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsLocalNetworking' "$packaged_plist")" == true ]]
if /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSAllowsArbitraryLoads' "$packaged_plist" >/dev/null 2>&1; then
    echo 'Packaged app must not disable transport security globally.' >&2
    exit 1
fi
assert_count "$CASE_ROOT/commands.log" '^swift build -c release --disable-sandbox$' 1
assert_count "$CASE_ROOT/submissions.log" '^app$' 1
assert_count "$CASE_ROOT/submissions.log" '^dmg$' 1
assert_count "$CASE_ROOT/commands.log" '^spctl ' 2
assert_count "$CASE_ROOT/commands.log" '^codesign --force .*--preserve-metadata=entitlements .*Downloader.xpc$' 1
assert_count "$CASE_ROOT/commands.log" '^codesign --force .*--deep' 0
[[ -L "$CASE_ROOT/dist/Smart Clipboard.app/Contents/Frameworks/Sparkle.framework/Versions/Current" ]]
python3 - "$CASE_ROOT/commands.log" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
signed = [line for line in lines if line.startswith('codesign --force')]
expected = ['Installer.xpc', 'Downloader.xpc', 'Autoupdate', 'Updater.app', 'Sparkle.framework', 'Clipboard.app']
assert all(signed[i].endswith(suffix) for i, suffix in enumerate(expected)), signed
PY
(cd "$CASE_ROOT/dist" && shasum -a 256 -c SHA256SUMS.txt >/dev/null)
[[ "$(cat "$CASE_ROOT/dist/notarization-release/dmg-input.sha256")" != "$(cat "$CASE_ROOT/dist/notarization-release/dmg-final.sha256")" ]]
run_release --resume
assert_count "$CASE_ROOT/submissions.log" '^app$' 1
assert_count "$CASE_ROOT/submissions.log" '^dmg$' 1
echo 'PASS accepted release, exact app packaging, final checksums, completed resume'

new_case app-pending
export MOCK_PENDING_STAGE=app
must_fail run_release
[[ ! -f "$CASE_ROOT/dist/SHA256SUMS.txt" ]]
must_fail run_release
assert_count "$CASE_ROOT/submissions.log" '^app$' 1
unset MOCK_PENDING_STAGE
run_release --resume
assert_count "$CASE_ROOT/submissions.log" '^app$' 1
assert_count "$CASE_ROOT/submissions.log" '^dmg$' 1
assert_count "$CASE_ROOT/commands.log" '^swift build -c release --disable-sandbox$' 1
echo 'PASS app timeout resumes without rebuilding or resubmitting'

new_case dmg-pending
export MOCK_PENDING_STAGE=dmg
must_fail run_release
[[ ! -f "$CASE_ROOT/dist/SHA256SUMS.txt" ]]
unset MOCK_PENDING_STAGE
run_release --resume
assert_count "$CASE_ROOT/submissions.log" '^app$' 1
assert_count "$CASE_ROOT/submissions.log" '^dmg$' 1
assert_count "$CASE_ROOT/commands.log" '^hdiutil create ' 1
echo 'PASS DMG timeout resumes without repackaging or resubmitting'

new_case invalid
export MOCK_INVALID_STAGE=app
must_fail run_release
[[ -f "$CASE_ROOT/dist/notarization-release/app-log.json" ]]
[[ ! -f "$CASE_ROOT/dist/notarization-release/complete" ]]
assert_count "$CASE_ROOT/commands.log" '^xcrun stapler staple ' 0
unset MOCK_INVALID_STAGE
echo 'PASS rejected notarization surfaces log and prevents stapling/publication'

new_case ambiguous-submit
export MOCK_SUBMIT_FAIL=true
must_fail run_release
unset MOCK_SUBMIT_FAIL
must_fail run_release --resume
assert_count "$CASE_ROOT/submissions.log" '^app$' 1
echo 'PASS ambiguous submission never automatically resubmits'

new_case wrong-identity
SIGNING_IDENTITY='Apple Development: Test Person' must_fail run_release
assert_count "$CASE_ROOT/commands.log" '^swift ' 0
SIGNING_IDENTITY='' must_fail run_release
NOTARY_PROFILE='' must_fail run_release
echo 'PASS missing/wrong identity and missing profile fail before build'

new_case different-certificate
export MOCK_CERT_MISMATCH=true
must_fail run_release
[[ ! -e "$CASE_ROOT/submissions.log" ]]
unset MOCK_CERT_MISMATCH
echo 'PASS certificate fingerprint mismatch prevents submission'

new_case changed-resume
export MOCK_PENDING_STAGE=app
must_fail run_release
unset MOCK_PENDING_STAGE
printf 'changed\n' >> "$CASE_ROOT/dist/Smart Clipboard.app/Contents/MacOS/SmartClipboard"
must_fail run_release --resume
assert_count "$CASE_ROOT/submissions.log" '^app$' 1
echo 'PASS changed executable cannot resume an existing submission'

new_case gatekeeper-failure
export MOCK_ASSESS_FAIL=true
must_fail run_release
[[ ! -f "$CASE_ROOT/dist/SHA256SUMS.txt" ]]
[[ ! -f "$CASE_ROOT/dist/notarization-release/complete" ]]
unset MOCK_ASSESS_FAIL
echo 'PASS Gatekeeper rejection prevents completion/checksums'

new_case preview
SIGNING_IDENTITY='' "$CASE_ROOT/scripts/package-release.sh" > "$CASE_ROOT/output.log" 2>&1
[[ -f "$CASE_ROOT/dist/SHA256SUMS.txt" ]]
assert_count "$CASE_ROOT/commands.log" '^codesign --force --sign - ' 1
assert_count "$CASE_ROOT/commands.log" '^xcrun ' 0
"$CASE_ROOT/scripts/package-release.sh" --existing-build > "$CASE_ROOT/output.log" 2>&1
assert_count "$CASE_ROOT/commands.log" '^swift build -c release --disable-sandbox$' 1
export MOCK_VERIFY_FAIL=true
must_fail "$CASE_ROOT/scripts/package-release.sh" --existing-build > "$CASE_ROOT/output.log" 2>&1
unset MOCK_VERIFY_FAIL
echo 'PASS ad-hoc preview, existing-build packaging, signature verification failure'
echo 'All release orchestration tests passed.'
