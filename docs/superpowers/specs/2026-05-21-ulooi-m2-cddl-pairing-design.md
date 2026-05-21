# Specification: ulooi M2 CBOR & Secure Pairing Client (iOS)

**Status:** Draft (Approved for implementation)
**Author:** Antigravity + Ryan
**Milestone:** Milestone 2 (UCLAW Pairing & Transport Client)

---

## 1. Context & Objectives

This specification details the client-side implementation on iOS (`ulooi` repository) to support mDNS-based discovery, cryptographic P2P QR pairing, and secure CBOR-over-WebSocket transport with the UCLAW desktop.

It establishes:
- Local P2P discovery using `Network` framework (`NWBrowser`).
- Ephemeral Diffie-Hellman key exchange (ECDH over Curve25519) for secure key generation.
- Long-term credentials saved in the secure iOS Keychain.
- Type-safe Swift `Codable` wrappers mapped from the unified CDDL envelope schema.

---

## 2. iOS Native Architecture

```
                  ┌─────────────────────────────────────┐
                  │        SwiftUI Views / App State    │
                  │   (OnboardingView, EmbodiedHome)    │
                  └──────────────────┬──────────────────┘
                                     ▼
                  ┌─────────────────────────────────────┐
                  │          PresenceDirector           │
                  │  (Coordinates Connection & Face)    │
                  └──────────────────┬──────────────────┘
                                     ▼
                  ┌─────────────────────────────────────┐
                  │          TransportManager           │
                  │  (mDNS Scan, WSS Lifecycle, Retry)  │
                  └──────┬───────────────────────┬──────┘
                         ▼                       ▼
           ┌───────────────────────────┐   ┌───────────────────────────┐
           │      PairingService       │   │       SecureStorage       │
           │ (ECDH, Ed25519 Handshake) │   │     (Apple Keychain)      │
           └───────────────────────────┘   └───────────────────────────┘
```

---

## 3. Detailed Components

### 3.1 Network Discovery (`TransportManager.swift`)

We will use Apple's native `Network` framework to implement `NWBrowser` for service discovery:

```swift
import Network

public class TransportManager: ObservableObject {
    private var browser: NWBrowser?
    @Published public var discoveredServers: [DiscoveredServer] = []
    
    public func startScanning() {
        let parameters = NWParameters()
        let browser = NWBrowser(for: .bonjour(type: "_uclaw-bridge._tcp", domain: nil), using: parameters)
        
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                DevLog.info("mDNS Browser is ready")
            case .failed(let error):
                DevLog.error("mDNS Browser failed: \(error)")
            default:
                break
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredServers = results.map { result in
                    let name = result.endpoint.debugDescription
                    // Resolve addresses ...
                    return DiscoveredServer(name: name, endpoint: result.endpoint)
                }
            }
        }
        
        self.browser = browser
        browser.start(queue: DispatchQueue.global(qos: .userInitiated))
    }
}
```

### 3.2 Secure Cryptographic Pairing (`PairingService.swift`)

Using Apple's `CryptoKit` for X25519 (ECDH) key derivation and static Ed25519 identity key signatures:

```swift
import CryptoKit
import Foundation

public struct PairingService {
    // Generate static identity keys if not already created
    public static func getOrCreateStaticIdentity() throws -> SecureEnclave.Sign.PublicKey {
        // Enforce secure enclave storage where available
        ...
    }
    
    // Derive symmetric encryption key via ECDH (X25519) + HKDF-SHA256
    public static func deriveSharedSecret(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        serverPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: Data
    ) throws -> SymmetricKey {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: "ulooi-pairing-v1".data(using: .utf8)!,
            outputByteCount: 32
        )
    }
}
```

### 3.3 Swift `Codable` Envelope (`WireEnvelope.swift`)

To preserve consistency, our models represent the identical types defined in `wire-envelope-v1.cddl`:

```swift
import Foundation

public struct WireEnvelope: Codable {
    public let v: Int
    public let id: String
    public let ts: UInt64
    public let src: String
    public let kind: String
    public let replyTo: String?
    public let payload: Data // CBOR Encoded sub-payload representation
    
    enum CodingKeys: String, CodingKey {
        case v
        case id
        case ts
        case src
        case kind
        case replyTo = "reply_to"
        case payload
    }
}
```

---

## 4. UI Integrations

- **Onboarding QR Scanner**: Integrates `AVFoundation` camera view capture to scan the desktop pairing QR code, parsing `uclaw://pair?host=...&port=...&pk_S_eph=...&salt=...&pk_S_static=...`.
- **Confirmation Dialogue**: Once the pairing connection establishes, displays the 4-digit code generated from `HKDF(K_shared, "confirm")` to match with the desktop console display.

---

## 5. Security & Isolation

- **Zero Global Writes**: Pairing session is strictly isolated; keys and credentials never persist to standard filesystems or shared UserDefaults.
- **Keychain Storage**: Pairs are persisted securely under high-grade accessibility control, set to `.afterFirstUnlockThisDeviceOnly` to prevent iCloud cloud-spill leakages.
