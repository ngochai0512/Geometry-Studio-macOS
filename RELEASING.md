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

Create the base64 value with:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

No provisioning profile is needed for a Developer ID macOS app. The project enables the
hardened runtime in `project.yml`, which notarization requires.

## What the workflow does

1. Generates `GeometryStudio.xcodeproj` from `project.yml`.
2. Archives a universal (`arm64` + `x86_64`) Release build signed with the Developer ID
   certificate and a secure timestamp.
3. Zips the app, submits it with `notarytool --wait`, staples the ticket to the `.app`,
   re-zips and writes a SHA-256 checksum.
4. Creates the GitHub release and attaches the zip and checksums.

## Local check without secrets

```sh
xcodegen generate
xcodebuild \
  -project GeometryStudio.xcodeproj \
  -scheme GeometryStudio \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

That produces a universal, unsigned app for inspection; it is not distributable.

## Not done yet

- Sparkle updates: no dependency, appcast URL or EdDSA keypair yet. The workflow publishes
  zips only.
- DMG packaging, Homebrew cask and Mac App Store distribution.
- A versioning policy beyond tags; `CFBundleShortVersionString` comes from the tag and
  `CFBundleVersion` from the workflow run number.
