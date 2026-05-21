# Plan: ulooi M2 Pairing & Transport Client (iOS)

This execution plan breaks down client-side development for Milestone 2 in the `ulooi` workspace.

---

## Task Checklist

- [ ] **Phase 1: Setup Schemas & Codegen**
  - [ ] Generate or declare Swift structures corresponding to [wire-envelope-v1.cddl](file:///Users/ryanliu/Documents/uclaw/ulooi/Schemas/wire-envelope-v1.cddl).
  - [ ] Add unit test suite validating CBOR round-trip serialization using `SwiftCBOR`.

- [ ] **Phase 2: Local mDNS Scanning**
  - [ ] Implement `TransportManager` using `Network` framework `NWBrowser`.
  - [ ] Scan for `_uclaw-bridge._tcp` services on the local sub-network.
  - [ ] Expose discovered endpoints in App State.

- [ ] **Phase 3: Cryptographic Pairing Handshake**
  - [ ] Implement `PairingService` using `CryptoKit` (ECDH, Ed25519 static keypair, HKDF salt-mix).
  - [ ] Add `SecureStorage` wrapper to read/write auth tokens using Apple Keychain services.
  - [ ] Validate pairing request encryption (AES-GCM-256 withderived $K_{shared}$).

- [ ] **Phase 4: UI Onboarding Workflow**
  - [ ] Integrate Camera QR code scanner in onboarding flow.
  - [ ] Display connection status alerts (Green/Yellow/Red status badges).
  - [ ] Implement pairing verification code view.

---

## Verification Criteria

### Compilation
- Build the `ulooi` targets successfully using Xcode or xcodebuild with 0 errors.

### Local Unit Tests
- Add and execute unit tests for `WireEnvelope` serialization inside `LooiKitTests` or main test targets:
  - Verify that invalid/malformed CBOR payloads fail decoding safely.
  - Verify that signatures match between server static public keys and client ephemeral signatures.
