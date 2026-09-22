# Developer ID signing and notarization

Public macOS downloads use a **Developer ID Application** identity. The app is distributed as a DMG and ZIP, so a Developer ID Installer certificate is not needed. The current app does not use capabilities that require a provisioning profile or extra hardened-runtime exceptions.

## Set up this Mac

1. In Keychain Access, use Certificate Assistant → Request a Certificate from a Certificate Authority. Save the request to disk, then upload it when creating a Developer ID Application certificate in the Apple Developer portal.
2. Install the downloaded certificate on the Mac that created the request. My Certificates must show the certificate with its matching private key.
3. Run `security find-identity -v -p codesigning`. It must list the Developer ID Application identity as valid. Record its SHA-1 identifier for `SIGNING_IDENTITY`.
4. If the certificate reports a missing intermediate, obtain **Developer ID – G2** from [Apple's certificate authority page](https://www.apple.com/certificateauthority/). Verify it chains to the existing Apple root and import it into the login keychain. Do not override certificate trust settings to hide a chain failure.
5. Create an app-specific password for notarization in your Apple Account. Store it locally with the interactive command below, substituting your Apple Account and developer Team ID. Enter the password only at the hidden prompt.

```sh
xcrun notarytool store-credentials "smart-clipboard-notary" \
  --apple-id "YOUR_APPLE_ACCOUNT" \
  --team-id "YOUR_TEAM_ID"
```

The profile contains credentials in Keychain. Private keys, app-specific passwords and exported identities do not belong in this repository or a release archive. Code signing may ask for access to your signing private key; authenticate directly in macOS when needed.

## Release acceptance

A distributable candidate must pass every signing gate:

- Valid Developer ID Application identity with the intended certificate and Team ID.
- App signature verifies; hardened runtime and a secure timestamp are present.
- Apple accepts the app submission; the notarization ticket is stapled and validates.
- The final ZIP and DMG contain that exact app, without rebuilding or re-signing it after notarization.
- The DMG itself is signed, accepted by Apple, and has a valid stapled ticket.
- Gatekeeper accepts the app and disk image. Extracted artifacts pass signature/ticket checks.
- SHA-256 checksums are computed after all signing and stapling. Uploaded/downloaded release assets match them.

Retain submission IDs and notarization logs with local release artifacts. A pending submission is not a successful notarization; continue checking its existing ID rather than making duplicate submissions. Signing acceptance is separate from the live product gates in [UAT.md](UAT.md).

The default development build remains ad-hoc signed. Setting `SIGNING_IDENTITY` signs with the selected identity using hardened runtime and a secure timestamp. The notarization script specifically requires a Developer ID Application identity. Public releases must complete notarization and verification before publication; a successful build alone is insufficient.

## Build the release

Run on the Mac with the installed signing identity and Keychain profile:

```sh
SIGNING_IDENTITY="YOUR_CERTIFICATE_SHA1" \
NOTARY_PROFILE="smart-clipboard-notary" \
NOTARY_TIMEOUT=60s \
./scripts/notarize-release.sh
```

The script builds once, signs and submits the app, staples its ticket, packages that same app, then signs and notarizes the DMG. It checks the final signatures, tickets and Gatekeeper assessments before writing `dist/SHA256SUMS.txt`. Release assets and submission records are kept in the ignored `dist/` directory. The current installed app is not changed. `dist/build-source.json` records the source commit, whether it was dirty, and the signed executable checksum; update publication requires the exact clean reviewed commit.

If Apple is still processing a submission, leave `dist/` unchanged and rerun the same command with `--resume` appended. This checks the existing submission instead of rebuilding or uploading again. A rejected or ambiguous submission requires diagnosis; inspect the recorded submission/result files and Apple's submission history before changing state.

Before publishing, mount the final DMG read-only and verify the embedded app's signature and stapled ticket. After uploading, download both assets again and compare their checksums with `SHA256SUMS.txt`.

The isolated orchestration checks use fake signing/notarization tools and do not access credentials:

```sh
bash Tests/ReleaseScripts/test-release.sh
python3 Tests/ReleaseScripts/test-release-update.py
python3 Tests/ReleaseScripts/test-compare-bundles.py
```

These checks cover failure and resume behavior; they do not substitute for Apple's actual acceptance or Gatekeeper checks.

## Sparkle framework and update keys

The app pins **Sparkle 2.10.0** through Swift Package Manager. `build-app.sh` invokes `embed-sparkle.sh` to copy the framework with its symlinks intact into `Contents/Frameworks`, add the app-relative runtime search path, and sign in this order: Installer XPC service, Downloader XPC service, Autoupdate, Updater app, framework, then the containing app. Downloader retains its entitlements. Developer ID builds apply hardened runtime and timestamps to nested code; development builds remain ad-hoc signed. `--deep` is used for verification only, never signing. This follows [Sparkle's manual signing instructions](https://sparkle-project.org/documentation/sandboxing/#code-signing).

The helper finds the framework beside the SwiftPM executable or in `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`; `SPARKLE_FRAMEWORK` can explicitly select another copy of the same pinned version. A missing framework or unexpected version fails packaging. Notarization verifies the signing certificate of each nested helper and framework as well as the app.

Use the `bin` tools from the official matching Sparkle distribution. The resolved package also includes them at `.build/artifacts/sparkle/Sparkle/bin`. On the authorized signing Mac, the owner creates the Ed25519 key in Keychain once:

```sh
SPARKLE_TOOLS="/path/to/Sparkle-2.10.0/bin"
"$SPARKLE_TOOLS/generate_keys" --account smart-clipboard
"$SPARKLE_TOOLS/generate_keys" --account smart-clipboard -p
```

Only the public key belongs in `SUPublicEDKey`. Keep the private key in Keychain: do not export it, pass it in arguments/environment variables, or commit it. The release scripts support only an existing Keychain account, check its public key against the signed app, and call `sign_update` without private-key arguments. The app must set `SUFeedURL` to `https://colombod.github.io/smart-clipboard/appcast.xml`, require signed feeds, and verify updates before extraction. Root signing setup owns these Info.plist values and key creation; preparation does not create or change keys.

## Prepare and publish a preview update

The all-provider and native accessibility gates remain unaccepted. The owner has authorized an opt-in preview after local capture, notifications, packaging and update checks, with the remaining limitations disclosed. **Do not present that preview as stable or fully accepted.** The complete criteria in UAT.md still apply before making those broader claims; these commands alone do not establish product readiness.

Commit the reviewed source/version/public-key configuration before the final build, then complete notarization. Builds use positive integer `CFBundleVersion` values. Every new update build must exceed all builds already in the feed, including preview builds. Preview tags are `v<marketing-version>-preview.<build>`; stable tags are `v<marketing-version>`. Stable entries have no channel element; preview entries use `sparkle:channel=preview`. Only users who explicitly opt into previews receive preview entries; a later higher-build stable entry can supersede them. See [Sparkle channels and versioning](https://sparkle-project.org/documentation/publishing/#channels).

For the proposed final 0.4.0 build 11 preview, prepare a signed feed locally after notarization:

```sh
python3 scripts/release-update.py prepare \
  --tag v0.4.0-preview.11 --channel preview \
  --notes docs/releases/v0.4.0-preview.md \
  --sparkle-tools "$SPARKLE_TOOLS" --first-feed
```

The notes file must already exist and contain the reviewed limitations. Use `--first-feed` only when the public feed returns 404 for its initial creation; omit it for subsequent updates. Preparation downloads and verifies an existing signed feed, retains older entries, signs the finalized ZIP, and signs the complete appcast with embedded plain-text notes. It writes `dist/update-release/release.json`, `release-notes.txt` and `appcast.xml`. Review all three; changing the feed or assets invalidates their recorded hashes. Preserve this directory before preparing another release. No release or feed is published by preparation. The manual feed construction uses [Sparkle's documented `sign_update` format](https://sparkle-project.org/documentation/publishing/); it creates no delta updates.

After approval, publish the exact reviewed commit/tag through the normal Git workflow. Publication requires the public tag to exist and resolve to the build commit; it never creates or moves tags. Then explicitly publish the downloadable assets:

```sh
python3 scripts/release-update.py publish-release --approve-tag v0.4.0-preview.11
```

This creates a draft if needed, uploads the finalized DMG, ZIP and checksums, marks the release as a prerelease without replacing GitHub's latest stable release, then downloads every asset anonymously over HTTPS and verifies size/checksum. A resumed draft reuses identical uploaded assets and refuses to overwrite different bytes. A failed download prevents proceeding to the feed; it does not roll back an already-public release. Diagnose and rerun verification rather than replacing public assets silently.

Separately approve and configure GitHub Pages from the repository's `gh-pages` branch, root directory, at the stated feed URL. The publisher does not create branches, enable Pages, or change its settings. Once that source is configured, publish the feed:

```sh
python3 scripts/release-update.py publish-feed \
  --approve-tag v0.4.0-preview.11 --sparkle-tools "$SPARKLE_TOOLS"
```

This **rechecks public assets before writing the feed**, verifies the signed feed, and rejects any change to the public feed or branch copy since preparation. It updates only `appcast.xml` through GitHub's contents API with the prior file revision. It neither deletes other Pages files nor suppresses signature checks. Pages deployment is asynchronous; afterward run:

```sh
python3 scripts/release-update.py verify-feed --sparkle-tools "$SPARKLE_TOOLS"
```

Verification requires the publicly served feed to match the reviewed signed bytes and every download to match its recorded checksum. A public feed check is separate from the real updater installation test. `verify-public` checks downloads alone. The scripts never promote a preview to stable; a future stable preparation requires a new build plus explicit `--approve-stable` after acceptance.

## Testing an update privately before publication

A signed/notarized local 0.4.0 build 10 can test updating to candidate build 11 with the same marketing version, before either candidate or feed is published. Preserve the **entire** bootstrap `dist` directory outside the repository before the final build: filenames use the marketing version, so the final build would replace those assets. Keep each completed notarization state and its checksums with its own build. Never invoke `--resume` against another build or change a submitted binary.

Use a loopback-only test server with a separately prepared appcast pointing to the final notarized ZIP. Sign both the ZIP and test appcast using the same Keychain-backed update key. Sparkle 2.10.0 supports a temporary `SUFeedURL` user-default override for testing; preserve any previous value, stop the app before changing it, and remove/restore the override when testing finishes. Keep signed-feed enforcement, archive verification and Developer ID validation enabled throughout. The public release scripts intentionally generate only public GitHub URLs; never upload the private test feed as the public feed.

Install the authorized bootstrap, opt into previews explicitly, and test a real Sparkle update to build 11 while checking preferences/history, permission continuity and the configured local provider. Confirm quiet scheduled checking separately from an explicitly requested install. Restore the original release preference and public HTTPS feed after the private test. Verify both successful installation and tampered-feed/archive rejection before publication. The release scripts do not install the app, enable preview preference, change permissions, or prove this migration succeeded. Returning from a preview to stable also requires a higher stable build number; channel changes do not authorize a downgrade.

## Updating the installed preview

The bundle identifier remains `com.smartclipboard.app`. Changing from ad-hoc signing to Developer ID changes its signing identity, so macOS may require renewed Screen Recording or saved-key approval once. Preserve history/settings and validate this migration separately. Do not claim future permission continuity solely from a valid signature.

The local 0.3.0-to-0.4.0 build 10 migration reproduced an enabled Screen Recording switch with denied app access: macOS logged a mismatch between the saved ad-hoc code requirement and the Developer ID identity. Off/on and restart did not repair that record. After the user's approval, a targeted `tccutil reset ScreenCapture com.smartclipboard.app` and adding the exact installed app in System Settings restored the app's permission check. This is a manual recovery for an obsolete development identity, not an automatic update action or evidence that capture-to-paste has passed. Never reset unrelated applications' approvals.

## Apple references

- [Create a certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)
- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Developer ID intermediate certificate](https://developer.apple.com/support/developer-id-intermediate-certificate/)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [App-specific passwords](https://support.apple.com/102654)
