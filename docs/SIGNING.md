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

The script builds once, signs and submits the app, staples its ticket, packages that same app, then signs and notarizes the DMG. It checks the final signatures, tickets and Gatekeeper assessments before writing `dist/SHA256SUMS.txt`. Release assets and submission records are kept in the ignored `dist/` directory. The current installed app is not changed.

If Apple is still processing a submission, leave `dist/` unchanged and rerun the same command with `--resume` appended. This checks the existing submission instead of rebuilding or uploading again. A rejected or ambiguous submission requires diagnosis; inspect the recorded submission/result files and Apple's submission history before changing state.

Before publishing, mount the final DMG read-only and verify the embedded app's signature and stapled ticket. After uploading, download both assets again and compare their checksums with `SHA256SUMS.txt`.

The isolated orchestration checks use fake signing/notarization tools and do not access credentials:

```sh
bash Tests/ReleaseScripts/test-release.sh
```

These checks cover failure and resume behavior; they do not substitute for Apple's actual acceptance or Gatekeeper checks.

## Updating the installed preview

The bundle identifier remains `com.smartclipboard.app`. Changing from ad-hoc signing to Developer ID changes its signing identity, so macOS may require renewed Screen Recording or saved-key approval once. Preserve history/settings and validate this migration separately. Do not claim future permission continuity solely from a valid signature.

## Apple references

- [Create a certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)
- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Developer ID intermediate certificate](https://developer.apple.com/support/developer-id-intermediate-certificate/)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [App-specific passwords](https://support.apple.com/102654)
