# Common Ground for iOS

Native SwiftUI client for federated [Common Ground](https://github.com/Common-Ground-DAO/commonground) instances.

This is a separate client repository. The server monorepo's generated OpenAPI document, socket catalog, protoo catalog, and headless TypeScript SDK are its protocol specification; no server or web-client code is imported here.

## Current milestone

The first protocol spine is implemented end-to-end:

- multi-instance onboarding begins with `GET /api/v2/Instance/config`;
- typed POST-RPC transport unwraps `{status,data|error}` even when errors use HTTP 200;
- per-instance URL sessions isolate rolling session cookies and persist them in the Keychain;
- P-256 device keys are generated in the Secure Enclave and exported as the server's exact public JWK shape;
- ECDSA signatures are normalized to raw 64-byte IEEE-P1363 and base64 encoded;
- ALTCHA v2 is solved natively with PBKDF2/HMAC-SHA256 while preserving all signed challenge fields;
- registration, password login, device-signature login, session status, and destructive logout are wrapped;
- valid sessions restore silently from cached login state on launch;
- stale device identities fall back to password login and superseded devices are retired when possible;
- Socket.IO connects at `/api/ws/`, retries transient initial failures, performs in-band device login, and routes all 18 `cli*` events;
- community channel history and structured text-message sends back the initial SwiftUI experience;
- adaptive native navigation uses compact iPhone flows and a three-column iPad layout;
- communities and direct-message sessions are distinct navigation surfaces, with explicit selection restoration;
- notification history, exact message/comment routing, in-app realtime banners, server-backed user search, public profiles, follows, and mutual-follow DMs are API-backed;
- public community discovery/create/join/leave and community, user, and message reporting are API-backed;
- replies, structured mentions, reactions, editing/deletion, image upload, and signed attachment rendering are native messaging features;
- Spark balances and non-refundable community contributions are native, alongside configurable community bot policy;
- account-scoped SQLite persistence provides offline launch, cached communities/chats/messages/users/notifications,
  durable per-conversation drafts, and a retryable message outbox;
- realtime reconnect performs in-band reauthentication, delta message reconciliation, structural refreshes,
  notification replay deduplication, and stable ISO timestamp ordering;
- community administration covers general assets/info, premium and renewal, onboarding/applications,
  newsletters, members and timed moderation, bans, channels/areas, roles and permissions, tokens,
  bots, and Common Ground app installation/permissions/removal;
- messaging includes local search, saved messages, pinned messages, first-unread markers,
  reply-thread navigation, URL previews, GIPHY search, image galleries, offline-aware sends, and
  ephemeral typing indicators for channels, DMs, and article comments;
- own REST writes are applied locally because the server deliberately sends no same-device echo.

The SDK is a standalone Swift package in `Sources/CommonGroundKit`; views contain no protocol code.

## Open and test

1. Open `CommonGroundApp.xcodeproj` in Xcode 16 or newer.
2. Select the `CommonGround` scheme and an iOS 17+ iPhone or iPad simulator/device.
3. Build and run.

Run the headless SDK tests with:

```sh
swift test
```

The live login contract can be checked without storing credentials in the repository:

```sh
COMMON_GROUND_LIVE_EMAIL='…' COMMON_GROUND_LIVE_PASSWORD='…' \
  swift test --filter CommonGroundKitTests.testLiveExistingAccountPasswordLoginContract
```

`COMMON_GROUND_LIVE_AUTH=1 swift test --filter CommonGroundKitTests.testLiveRegistrationAndPasswordLoginContract`
runs the registration-to-password-login path with a generated disposable account. Both live probes are opt-in and skipped during normal test runs.

The default onboarding target is `https://cg.mogged.eu`. Plain HTTP is accepted only for `localhost`, `127.0.0.1`, and `::1`, including the disposable conformance target at `http://127.0.0.1:18080`.

## Architecture

```text
CommonGroundApp (SwiftUI, session orchestration)
        │
CommonGroundKit (Swift package)
        ├── Transport / instance config
        ├── Secure-Enclave identity / auth / ALTCHA
        ├── Socket.IO event routing / normalized store
        ├── SQLite cache, drafts, and durable outbox
        └── Typed social domain APIs
```

See [docs/ROADMAP.md](docs/ROADMAP.md) for the deliberate milestone boundaries,
[docs/CONTRACT_FINDINGS.md](docs/CONTRACT_FINDINGS.md) for mobile-specific decisions,
and [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for the centralized publisher placeholders.
