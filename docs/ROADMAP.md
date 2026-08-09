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
- Ephemeral typing presence is implemented end to end for community channels, direct messages, and
  joined article comment rooms, including refresh, explicit stop, reconnect cleanup, and stale-state expiry.
- Community events are native: per-community discovery, cross-community “My events”, attendance,
  external/reminder event creation, role audiences, image uploads, and authorized edit/delete flows.
  Native calls and broadcasts deliberately remain in the calls workstream.
- The global Feed presents community articles and upcoming events with deterministic pagination,
  Explore/My communities scope, content and attendance controls, consistent community-topic filters,
  batch community identity hydration, and a retained public-community browser.
- Community apps have a native store/install surface and an isolated, non-persistent WebKit runtime.
  The bridge validates plugin identity/origin, forwards signed backend requests, rate-limits calls,
  prompts for declared sensitive permissions, gates camera/microphone, and routes safe internal links.
- Community administrators can reorder areas/channels, pin and remove messages, remove all channel
  messages from a member, and open role/ban moderation directly from message context menus.

## M1.1 — release hardening

- Add account deletion after backend issue #54 resolves the policy/API backlog.
- Add user blocking after backend issue #55 resolves the policy/API backlog.
- Add arbitrary file picking/browsing after backend issue #58 defines generic attachment metadata.
- Add passkeys after backend issue #66 supplies a secure native ceremony handoff for arbitrary instances.
- Complete translation coverage beyond the checked-in string-catalog foundation.
- Expand UI automation from onboarding/accessibility smoke tests to authenticated iPhone/iPad journeys.
- Fill the live supported-instance matrix for each release. Privacy manifests, dual-device CI, and the
  manual TestFlight upload pipeline are implemented.

## M2 — server-coordinated push

APNs cannot consume the existing web-push subscription. Implement after the publisher-run push gateway contract defines device registration, payload privacy, token rotation, and instance authentication.

## M3 — calls (independent workstream)

Implement protoo signaling from the documented handshake, then mediasoup/WebRTC transports, CallKit, audio-session management, camera, and PushKit ringing. Calls do not block the messaging MVP.

## Release gates

- Server-side user blocking (Apple UGC guideline 1.2).
- Nutrition labels, account deletion, moderation contact, age rating, and publisher metadata.
- Maintainer decision on iOS token/payment surfaces.
- Signing, TestFlight, and a live compatibility matrix for supported API/socket versions.
