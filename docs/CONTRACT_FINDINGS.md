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

## N-05 — push gateway contract is still required

The current `registerWebPushSubscription` endpoint cannot register an APNs token. iOS push is intentionally not shimmed; it needs the publisher-run gateway planned by the native-client roadmap.
