# Native contract findings

This log mirrors the reference client's `sdk/conformance/FINDINGS.md` style. Items here are iOS integration decisions or server coordination needs; established upstream findings remain authoritative in the monorepo.

## N-01 — Security.framework signature representation

`SecKeyCreateSignature(...ecdsaSignatureMessageX962SHA256...)` returns an ASN.1 DER/X9.62 ECDSA signature, while Common Ground validates WebCrypto's fixed-width IEEE-P1363 `r || s` representation. `SecureEnclaveDeviceKey` parses DER integers, removes sign padding, pads each coordinate to 32 bytes, concatenates them, and only then base64-encodes. A unit test pins padding behavior and the software-key path pins the 64-byte result.

## N-02 — Secure Enclave is unavailable in Simulator

Physical-device builds fail closed when Secure Enclave key creation fails. Simulator builds use a P-256 CryptoKit key stored as a this-device-only Keychain generic password so the complete protocol can be exercised. That fallback is compiled only for Simulator.

## N-03 — reCAPTCHA registration needs a platform flow

ALTCHA and `off` registration are native (`off` sends the web client's established `stub` token). An instance configured for reCAPTCHA currently presents a clear unsupported-registration error; password and saved-device login remain available. A future milestone should use an instance-owned web authentication ceremony rather than embedding shared Google credentials in the app.

## N-04 — logout requires coordinated local destruction

The server soft-deletes the device row on logout. The app therefore disconnects realtime, deletes the per-instance local key and device id, and creates a fresh key for the next password login. Retaining the old Secure Enclave key would create a permanently unusable identity.

Device ids and keys can also drift independently across reinstall, Keychain reset, or server-side deletion. `INVALID_SIGNATURE` and `NOT_FOUND` during device login therefore clear both local identity halves, regenerate the key, and return the user to password authentication. When a user deliberately chooses password login while an older device identity is still valid, the app authenticates that identity in an isolated cleanup session and retires it only after the replacement login succeeds.

## N-05 — push gateway contract is still required

The current `registerWebPushSubscription` endpoint cannot register an APNs token. iOS push is intentionally not shimmed; it needs the publisher-run gateway planned by the native-client roadmap. While the app is active, `cliNotificationEvent` drives native in-app banners and exact destination routing; this complements APNs but cannot replace background delivery.

## N-06 — sessions are isolated and restored per instance

The process-wide `HTTPCookieStorage.shared` can blur ownership when several Common Ground instances are used. Each default `HTTPTransport` now owns an ephemeral cookie jar and mirrors only that instance's cookies into a dedicated Keychain item. A successful login response is cached separately by instance; on launch, `checkLoginStatus` validates the rolling cookie and the app hydrates the matching cached response without asking the user to authenticate again.

## N-07 — deployed unread count is string-encoded

The TypeScript `User/login` contract declares `unreadNotificationCount` as a number, but the deployed PostgreSQL-backed response currently serializes it as an integer string. `LoginResponse` accepts both forms and normalizes them to `Int`. An opt-in live login test pins the deployed payload in addition to the source-derived fixture tests.

## N-08 — notification and search count fields cross PostgreSQL numeric boundaries

`Notification/getUnreadCount` is backed by SQL `COUNT` and can arrive as an integer string, matching reference-client finding F-08. Search priority is produced by a SQL aggregate and may likewise cross the wire as a string depending on the PostgreSQL driver’s numeric parser. The Swift APIs accept either JSON representation and normalize both to `Int` at the SDK boundary.

## N-09 — community counts and required creation nulls

Community list/detail member counts can cross the PostgreSQL boundary as strings, while `Community/createCommunity` strictly requires the three image-id keys even before images are selected. The Swift client normalizes either count representation and explicitly encodes the required `null` image values.

## N-10 — image upload success is not an API envelope

`File/uploadImage` is the sole multipart route and returns its upload result as a bare JSON object, while failures retain the normal `{status:"ERROR"}` envelope. `HTTPTransport.callMultipart` handles both shapes, preserves the instance cookie lifecycle, and leaves signed attachment downloads unauthenticated as designed.

## N-11 — article publication workaround resolved upstream

Resolved by backend PR #56 / issue #52 (reference findings F-13 and F-14), deployed on `cg.mogged.eu`. User and community article creation now publishes in one request when `published` contains an ISO timestamp, and the response returns the stored publication value. The iOS client therefore sends the intended draft/published state directly to `createArticle`; it does not create a draft and immediately update it. User article metadata-only updates no longer require a no-op `article: { articleId }` stub, although real edits correctly include the changed shared article body.

## N-12 — channel writes exclude the server-managed Admin role

`Community/createChannel` requires a non-null `areaId`, but callers must omit the predefined Admin role from `rolePermissions`. The server rejects a supplied Admin entry with `NOT_ALLOWED` and injects its canonical full-access preset itself; `updateChannel` follows the same rule. The Swift API filters Admin defensively and the channel editor requires an area before creation. A contract test pins the outgoing role list so this does not regress into a misleading authorization error.

## N-13 — offline state is account-scoped and the outbox is durable

The native cache uses SQLite in WAL mode and is scoped by normalized instance URL plus user id. It stores the own-user snapshot, communities, chats, messages, hydrated users, and notifications without treating cached state as authoritative after reconnect. Drafts are keyed by conversation access, and queued sends retain their client-generated UUID so retries remain idempotent. Files use complete-until-first-user-authentication protection; logout removes the account's local database even when server logout fails. Reconnect first attempts `Message/loadUpdates` for the cached time window, applies updates/deletes, and falls back to a full history load if delta reconciliation fails.

## N-14 — typing presence resolved; generic files remain backend-dependent

Resolved by backend PR #59 / issue #57, deployed on `cg.mogged.eu`. The iOS client emits fire-and-forget `setTyping { access, isTyping }`, refreshes active composition every 3.5 seconds, and routes the flat `cliTypingEvent { access, userId, isTyping }` response. Receiver state expires after seven seconds so a missed stop self-heals; local state is also cleared on socket interruption, while explicit stops are sent on inactivity, input blur, send, and navigation. Authorization and delivery scope remain server-owned (`CHANNEL_WRITE` for community channels, membership for DMs and joined article rooms), and calls intentionally have no typing surface.

## N-15 — socket transport state is not authentication state

Backend issue #61 tracks a server bug where the Socket.IO `login` handler can acknowledge `OK` when its signable-secret guard does not run, leaving the connection anonymous and outside authenticated rooms. Separately, the deployed production transport expects the web client's polling-first negotiation; forcing a direct WebSocket can stall behind the reverse proxy without a connect/error callback. The iOS client now uses polling with Socket.IO upgrade, enforces a connection timeout, models transport connection and authentication separately, verifies server presence after login, refuses to emit typing from an unauthenticated socket, applies `cliUserData` presence patches, and creates a fresh REST + socket session after returning from the background. This also avoids presenting the local user as online merely because no warning banner is visible.

Uploads and message attachments still model images only. The native gallery therefore handles image attachments, while a true document/file browser waits for the typed metadata, policy, and download semantics tracked in backend issue #58.

## N-16 — community events and plugins are native surfaces

The iOS client mirrors the deployed community-event contracts for listing, detail, attendance, and authorized creation/update/deletion. `Community/getMyEvents` backs a cross-community native agenda and paginates incrementally with the `(scheduledBefore, beforeId)` cursor fixed by backend PR #68 / issue #67. Backend PR #70 / issue #69 subsequently made the matching `(scheduleDate, id)` ordering deterministic on first and cursor pages. Pages are still deduplicated defensively and pull-to-refresh resets the cursor. Event `call` and `broadcast` records can be read, but joining them remains intentionally scoped to the later calls workstream. The app-store runtime uses the signed `Plugins/pluginRequest` route instead of exposing the user's API session to plugin JavaScript. Each plugin receives a non-persistent WebKit data store and a narrow message bridge; identity, iframe origin, declared permissions, navigation, media capture, and request rate are enforced natively.

## N-17 — native passkeys need an explicit session handoff

The deployed passkey flow relies on a cookie shared between the main web origin and `id.<instance>`, plus a Socket.IO event routed to that exact browser session. An arbitrary self-hosted instance cannot be predeclared in an iOS Associated Domains entitlement, and `ASWebAuthenticationSession` does not safely transfer its browser cookie jar into the app's isolated `URLSession`. The client therefore does not copy cookies or pretend the web ceremony is native login. Backend issue #66 requests a verifier-bound, expiring, single-use authorization-code handoff; password and saved-device login remain available until that contract lands.

## N-18 — moderation gaps are explicit backend work

Existing contracts support timed/indefinite bans, role assignment, application decisions, message deletion, and moderator deletion of all messages from a channel member. A true kick-without-ban, durable moderator warnings, and a paginated administrative audit log do not have contracts; backend issues #63, #64, and #65 track those separately. The app does not encode these actions as misleading combinations of role or ban calls.

## N-19 — the global Feed has stable, consistent discovery contracts

Backend PR #75 / issue #74 introduced `Feed/getPostList`: one authorization-aware, deterministic newest-first stream that combines published user and community posts behind a single `(publishedAt, postId)` cursor. Its actor, scope, topic, and community-verification filters are applied server-side; the response supplies a structured, bounded `bodyPreview`, complete media references, comment count, viewer capabilities, and actor/creator identity. Follow-ups #76–#78 / PR #79 fixed preview truncation, protected community visibility behind `ARTICLE_READ`, corrected anonymous commenting capability, and included the viewer's own posts in Following. Issue #80 / PR #81 completed the agreed v1 contract before the native integration.

The iOS Feed calls only this unified route, renders user and community posts through the same card, opens the original article for the full body/comments, pages strictly from the last returned post, defensively deduplicates IDs, signs every supplied actor/creator/media object, and persists snapshots per complete filter query. Events remain a separate surface and continue to use `Community/getUpcomingEvents`; the earlier article-list pagination and community-topic work from PR #73 remains relevant to article-specific screens, not the global Feed.
