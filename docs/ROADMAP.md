# iOS delivery roadmap

## M0 — protocol spine (implemented)

Transport, instance discovery, Secure Enclave identity, native ALTCHA, registration/login/logout, Socket.IO authentication/event routing, normalized memory store, and a usable channel/message shell.

## M1 — mobile MVP breadth (implemented)

- Native adaptive iPhone/iPad navigation, centralized publisher configuration,
  community browsing, and direct-message plumbing are implemented as the M1 foundation.
- Notification history/read state and public-profile search/follow/DM flows are
  implemented against the reference-client contracts.
- Public community discovery, creation, joining/leaving, and UGC report submission
  are implemented with native iPhone/iPad surfaces.
- Rich messaging covers replies, structured mentions, emoji reactions,
  editing/deletion, image uploads, and signed media downloads.
- Native SQLite persists account-scoped communities, chats, messages, users, and notifications,
  plus durable per-conversation drafts and a retryable send outbox. Offline launch hydrates directly
  from this cache and reconnect reconciles message deltas before falling back to a full load.
- Community administration covers general metadata/assets, premium renewal, onboarding and pending
  applications, newsletters, members, timed moderation, bans, areas/channels, roles/permissions,
  tokens, bots, and plugin discovery/installation/permission management/removal.
- Messaging includes local search, saved/pinned messages, unread markers, reply-thread navigation,
  URL previews, instance-configured GIPHY search, and an image attachment gallery.

## M1.1 — release hardening

- Add account deletion when the server resolves the policy/API backlog.
- Add user blocking when the server resolves the policy/API backlog.
- Consume realtime typing presence after backend issue #57 defines the authenticated ephemeral contract.
- Add arbitrary file picking/browsing after backend issue #58 defines generic attachment metadata.
- Add passkeys through AuthenticationServices plus `ASWebAuthenticationSession` fallback for arbitrary instances.
- Complete localization, VoiceOver/UI automation, privacy manifests, and the supported-instance compatibility matrix.

## M2 — server-coordinated push

APNs cannot consume the existing web-push subscription. Implement after the publisher-run push gateway contract defines device registration, payload privacy, token rotation, and instance authentication.

## M3 — calls (independent workstream)

Implement protoo signaling from the documented handshake, then mediasoup/WebRTC transports, CallKit, audio-session management, camera, and PushKit ringing. Calls do not block the messaging MVP.

## Release gates

- Server-side user blocking (Apple UGC guideline 1.2).
- Privacy manifest, nutrition labels, account deletion, moderation contact, age rating.
- Maintainer decision on iOS token/payment surfaces.
- Signing, TestFlight, and a live compatibility matrix for supported API/socket versions.
