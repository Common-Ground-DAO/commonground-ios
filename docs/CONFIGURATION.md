# Publisher configuration

The repository ships with safe development placeholders. A publisher can
prepare a branded build without searching through feature code.

## Product and support values

Edit `CommonGroundApp/App/AppConfiguration.swift`:

- `productName` — customer-facing app name used in navigation;
- `defaultInstanceURL` — pre-filled instance during onboarding;
- `supportEmail` — support link in Account;
- `privacyURL` — privacy-policy link in Account;
- `AppTheme.accent` and `secondaryAccent` — global tint and generated-avatar colors.

Replace `CommonGroundApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and the
accent-color asset when final brand artwork is available.

## Apple signing and distribution

In the CommonGround target’s Build Settings, replace:

- bundle identifier `org.commonground.ios`;
- the empty Development Team;
- marketing version `0.1.0` and build number `1` as releases are prepared.

The target supports iPhone and iPad and has an iOS 17 deployment target.

## Backend-dependent placeholders

The notification timeline will use the native notification endpoints as they
are ported. Remote push remains disabled until the publisher-operated APNs
gateway contract is available. Calls remain a separate mediasoup/WebRTC
milestone. Neither placeholder fabricates local data.
