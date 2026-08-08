# Releasing Common Ground for iOS

## Continuous integration

`ios-ci.yml` builds the universal iPhone/iPad target without signing and runs the Swift package tests on every push to `main`, every pull request, and on demand.

## TestFlight

The `TestFlight` workflow is intentionally manual. Configure the `testflight` GitHub environment with these secrets before its first run:

- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64` — the base64-encoded contents of the `.p8` private key

Run the workflow with the desired marketing version. The GitHub run number becomes the unique build number. Xcode handles managed App Store distribution signing and uploads the archive directly to App Store Connect.

## Publisher-owned release metadata

Before external TestFlight distribution, the publisher must confirm the bundle identifier and Apple team, privacy nutrition labels, moderation contact, age rating, support/privacy URLs, export compliance, screenshots, and the supported-instance compatibility matrix. The checked-in privacy manifest declares the app's current required-reason API use; rerun Xcode's privacy report whenever dependencies or storage code change.

## Supported instance matrix

| Instance build | Status | Notes |
| --- | --- | --- |
| `cg.mogged.eu` / `develop` | Development reference | Used for live contract validation. |
| Current `develop` SHA | Required before release | Record the validated server SHA in the release notes. |
| Older or modified instances | Best effort | Instance discovery and API errors remain user-visible; no silent compatibility promise. |
