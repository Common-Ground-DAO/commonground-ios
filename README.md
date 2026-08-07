# Common Ground for iOS

Native SwiftUI client for federated [Common Ground](https://github.com/Common-Ground-DAO/commonground) instances.

This is a separate client repository. The server monorepo's generated OpenAPI document, socket catalog, protoo catalog, and headless TypeScript SDK are its protocol specification; no server or web-client code is imported here.

## Current milestone

The first protocol spine is implemented end-to-end:

- multi-instance onboarding begins with `GET /api/v2/Instance/config`;
- typed POST-RPC transport unwraps `{status,data|error}` even when errors use HTTP 200;
- per-instance URL sessions retain the rolling session cookie;
- P-256 device keys are generated in the Secure Enclave and exported as the server's exact public JWK shape;
- ECDSA signatures are normalized to raw 64-byte IEEE-P1363 and base64 encoded;
- ALTCHA v2 is solved natively with PBKDF2/HMAC-SHA256 while preserving all signed challenge fields;
- registration, password login, device-signature login, session status, and destructive logout are wrapped;
- Socket.IO connects at `/api/ws/`, performs in-band device login, and routes all 17 `cli*` events;
- community channel history and structured text-message sends back the initial SwiftUI experience;
- own REST writes are applied locally because the server deliberately sends no same-device echo.

The SDK is a standalone Swift package in `Sources/CommonGroundKit`; views contain no protocol code.

## Open and test

1. Open `CommonGroundApp.xcodeproj` in Xcode 16 or newer.
2. Select the `CommonGround` scheme and an iOS 16+ simulator or device.
3. Build and run.

Run the headless SDK tests with:

```sh
swift test
```

The default onboarding target is `https://cg.mogged.eu`. Plain HTTP is accepted only for `localhost`, `127.0.0.1`, and `::1`, including the disposable conformance target at `http://127.0.0.1:18080`.

## Architecture

```text
CommonGroundApp (SwiftUI, session orchestration)
        │
CommonGroundKit (Swift package)
        ├── Transport / instance config
        ├── Secure-Enclave identity / auth / ALTCHA
        ├── Socket.IO event routing / normalized store
        └── Typed social domain APIs
```

See [docs/ROADMAP.md](docs/ROADMAP.md) for the deliberate milestone boundaries and [docs/CONTRACT_FINDINGS.md](docs/CONTRACT_FINDINGS.md) for mobile-specific decisions.
