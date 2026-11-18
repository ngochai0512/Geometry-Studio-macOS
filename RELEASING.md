# Releasing

Releases are built by `.github/workflows/release.yml` and published to GitHub Releases.
Pushing a tag such as `v0.1.0` starts the workflow; the version is the tag without the `v`.

## Required repository secrets

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12` | Base64 of a `Developer ID Application` certificate exported as `.p12`. |
| `DEVELOPER_ID_P12_PASSWORD` | Password for that `.p12`. |
| `APPLE_TEAM_ID` | Apple Developer team identifier. |
| `APPLE_ID` | Apple ID used for notarization. |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID. |

These secrets are optional. When none of them is configured the workflow logs a warning, skips
certificate import and notarization, and publishes `GeometryStudio-<version>-unsigned.zip`. An
unsigned build is useful for smoke-testing a tag, but Gatekeeper blocks it on other Macs. When
only some are configured the workflow fails instead of quietly shipping an unsigned build.

Create the base64 value with:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

No provisioning profile is needed for a Developer ID macOS app. The project enables the
hardened runtime in `project.yml`, which notarization requires.

## What the workflow does

1. Validates the checked-in `GeometryStudio.xcodeproj`, including the settings Xcode wrote when
   it upgraded the project. The workflow does not regenerate it.
2. Checks the signing secrets. With all five present, imports the Developer ID certificate and
   archives an `arm64` Release build signed with a secure timestamp; otherwise archives it
   unsigned.
3. Signs and notarizes when the certificate is present: zip, `notarytool --wait`, staple the
   ticket, re-zip. Without it, zips the unsigned app with an `-unsigned` suffix. Either way it
   writes a SHA-256 checksum.
4. Creates the GitHub release and attaches the zip and checksums; an unsigned release body says
   so instead of generating notes.

## Local check without secrets

```sh
xcodebuild \
  -project GeometryStudio.xcodeproj \
  -scheme GeometryStudio \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The project is checked in, so no XcodeGen step is needed; regenerate only after a deliberate
`project.yml` change. This produces an unsigned app for inspection; it is not distributable.

## Not done yet

- Sparkle updates: no dependency, appcast URL or EdDSA keypair yet. The workflow publishes
  zips only.
- DMG packaging, Homebrew cask and Mac App Store distribution.
- A versioning policy beyond tags; `CFBundleShortVersionString` comes from the tag and
  `CFBundleVersion` from the workflow run number.
