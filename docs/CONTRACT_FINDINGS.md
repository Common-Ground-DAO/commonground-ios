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

Uploads and message attachments still model images only. The native gallery therefore handles image attachments, while a true document/file browser waits for the typed metadata, policy, and download semantics tracked in backend issue #58.
