# iOS delivery roadmap

## M0 — protocol spine (implemented)

Transport, instance discovery, Secure Enclave identity, native ALTCHA, registration/login/logout, Socket.IO authentication/event routing, normalized memory store, and a usable channel/message shell.

## M1 — mobile MVP breadth

- Native adaptive iPhone/iPad navigation, centralized publisher configuration,
  community browsing, and direct-message plumbing are implemented as the M1 foundation.
- Notification history/read state and public-profile search/follow/DM flows are
  implemented against the reference-client contracts.
- Complete generated models/wrappers for communities, chats, notifications, search, profiles, files, and article reading.
- Replace the in-memory sync store with GRDB/SQLite and add delta resync/offline reads.
- Add image upload/download, mentions, reactions, replies, moderation/reporting surfaces, account deletion, accessibility, localization, and full UI test coverage.
- Add passkeys through AuthenticationServices plus `ASWebAuthenticationSession` fallback for arbitrary instances.

## M2 — server-coordinated push

APNs cannot consume the existing web-push subscription. Implement after the publisher-run push gateway contract defines device registration, payload privacy, token rotation, and instance authentication.

## M3 — calls (independent workstream)

Implement protoo signaling from the documented handshake, then mediasoup/WebRTC transports, CallKit, audio-session management, camera, and PushKit ringing. Calls do not block the messaging MVP.

## Release gates

- Server-side user blocking (Apple UGC guideline 1.2).
- Privacy manifest, nutrition labels, account deletion, moderation contact, age rating.
- Maintainer decision on iOS token/payment surfaces.
- Signing, TestFlight, and a live compatibility matrix for supported API/socket versions.
