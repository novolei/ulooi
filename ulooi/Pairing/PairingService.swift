import Foundation
import CryptoKit

/// Parameters extracted from a pairing QR code URI.
/// Format: uclaw://pair?host=<host>&port=<port>&pk_S_eph=<hex>&salt=<hex>&pk_S_static=<hex>
public struct PairingParameters: Sendable {
    public let host: String
    public let port: Int
    public let serverEphemeralPublicKey: Curve25519.KeyAgreement.PublicKey
    public let salt: Data
    public let serverStaticPublicKey: Curve25519.Signing.PublicKey
    
    public init(
        host: String,
        port: Int,
        serverEphemeralPublicKey: Curve25519.KeyAgreement.PublicKey,
        salt: Data,
        serverStaticPublicKey: Curve25519.Signing.PublicKey
    ) {
        self.host = host
        self.port = port
        self.serverEphemeralPublicKey = serverEphemeralPublicKey
        self.salt = salt
        self.serverStaticPublicKey = serverStaticPublicKey
    }
}

/// Cryptographic service that manages the secure P2P QR handshake.
/// Handles key generation, Curve25519 ECDH key agreement, HKDF derivations, AES-GCM decryption, and Ed25519 signatures.
public final class PairingService: Sendable {
    
    public static let shared = PairingService()
    
    private init() {}
    
    /// Retrieve the client's persistent static Ed25519 identity key, or create it if not found.
    public func getOrCreateClientStaticIdentity() throws -> Curve25519.Signing.PrivateKey {
        if let storedData = SecureStorage.shared.clientStaticPrivateKey {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: storedData)
        }
        
        let newKey = Curve25519.Signing.PrivateKey()
        SecureStorage.shared.clientStaticPrivateKey = newKey.rawRepresentation
        return newKey
    }
    
    /// Parse QR code URI string into structured PairingParameters.
    public func parsePairingURI(_ uriString: String) -> PairingParameters? {
        guard let url = URL(string: uriString),
              url.scheme == "uclaw",
              url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        let queryItems = components.queryItems ?? []
        guard let host = queryItems.first(where: { $0.name == "host" })?.value,
              let portStr = queryItems.first(where: { $0.name == "port" })?.value,
              let port = Int(portStr),
              let pkSephHex = queryItems.first(where: { $0.name == "pk_S_eph" })?.value,
              let saltHex = queryItems.first(where: { $0.name == "salt" })?.value,
              let pkSstaticHex = queryItems.first(where: { $0.name == "pk_S_static" })?.value else {
            return nil
        }
        
        guard let pkSephData = Data(hexString: pkSephHex),
              let saltData = Data(hexString: saltHex),
              let pkSstaticData = Data(hexString: pkSstaticHex) else {
            return nil
        }
        
        do {
            let serverEphKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pkSephData)
            let serverStaticKey = try Curve25519.Signing.PublicKey(rawRepresentation: pkSstaticData)
            
            return PairingParameters(
                host: host,
                port: port,
                serverEphemeralPublicKey: serverEphKey,
                salt: saltData,
                serverStaticPublicKey: serverStaticKey
            )
        } catch {
            print("❌ Failed to instantiate CryptoKit keys from QR params: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Prepares the pairing request by generating an ephemeral X25519 keypair, 
    /// calculating the Ed25519 identity signature, and deriving the symmetric handshake key (K_shared).
    ///
    /// - Parameters:
    ///   - params: Parsed pairing parameters from the QR code.
    ///   - clientName: Friendly device name (e.g. "Ryan's iPhone").
    /// - Returns: A tuple of the constructed PairingRequest model, the derived SymmetricKey, and the client's ephemeral private key.
    public func preparePairingRequest(
        params: PairingParameters,
        clientName: String
    ) throws -> (PairingRequest, SymmetricKey, Curve25519.KeyAgreement.PrivateKey) {
        
        // 1. Generate client ephemeral keypair (X25519)
        let clientEphPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let clientEphPublicKey = clientEphPrivateKey.publicKey
        
        // 2. Fetch/Create client long-term static identity keypair (Ed25519)
        let clientStaticPrivateKey = try getOrCreateClientStaticIdentity()
        let clientStaticPublicKey = clientStaticPrivateKey.publicKey
        
        // 3. Compute client signature: Sign_sk_client_static(pk_C_eph || pk_S_eph)
        var messageToSign = Data()
        messageToSign.append(clientEphPublicKey.rawRepresentation)
        messageToSign.append(params.serverEphemeralPublicKey.rawRepresentation)
        
        let signature = try clientStaticPrivateKey.signature(for: messageToSign)
        
        // 4. Derive symmetric key via ECDH (X25519) + HKDF-SHA256
        let sharedSecret = try clientEphPrivateKey.sharedSecretFromKeyAgreement(with: params.serverEphemeralPublicKey)
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: params.salt,
            sharedInfo: "ulooi-pairing-v1".data(using: .utf8)!,
            outputByteCount: 32
        )
        
        // 5. Build pairing request
        let request = PairingRequest(
            clientStaticPk: clientStaticPublicKey.rawRepresentation,
            clientEphPk: clientEphPublicKey.rawRepresentation,
            clientName: clientName,
            signature: signature
        )
        
        return (request, derivedKey, clientEphPrivateKey)
    }
    
    /// Verifies the server's pairing response, validates the identity signature,
    /// decrypts the long-term auth token, and commits everything to SecureStorage.
    ///
    /// - Parameters:
    ///   - response: The pairing response returned from the server.
    ///   - params: Original pairing parameters from the QR code.
    ///   - derivedKey: The derived symmetric handshake key.
    ///   - clientEphPublicKeyData: The raw representation of the client's ephemeral public key.
    /// - Returns: True if pairing verification succeeds and token is securely stored.
    public func completePairing(
        response: PairingResponse,
        params: PairingParameters,
        derivedKey: SymmetricKey,
        clientEphPublicKeyData: Data
    ) throws -> Bool {
        
        // 1. Verify server's signature: Sign_sk_server_static(pk_S_eph || pk_C_eph)
        var messageToVerify = Data()
        messageToVerify.append(params.serverEphemeralPublicKey.rawRepresentation)
        messageToVerify.append(clientEphPublicKeyData)
        
        guard params.serverStaticPublicKey.isValidSignature(response.signature, for: messageToVerify) else {
            print("❌ Pairing Signature Verification Failed: Server signature was invalid.")
            return false
        }
        
        // 2. Decrypt the long-term auth token (token_auth) using AES-GCM-256 and derivedKey
        // The encrypted token payload carries the initialization vector and authentication tag.
        let sealedBox = try AES.GCM.SealedBox(combined: response.tokenAuth)
        let decryptedToken = try AES.GCM.open(sealedBox, using: derivedKey)
        
        guard decryptedToken.count == 32 else {
            print("❌ Pairing Decryption Succeeded but token length is invalid: \(decryptedToken.count) bytes (expected 32).")
            return false
        }
        
        // 3. Commit paired identity and credentials to SecureStorage
        SecureStorage.shared.serverStaticPublicKey = params.serverStaticPublicKey.rawRepresentation
        SecureStorage.shared.authToken = decryptedToken
        SecureStorage.shared.pairedServerName = params.host
        
        print("✅ Pairing Handshake Completed Successfully! Credentials stored securely in Keychain.")
        return true
    }
    
    /// Generate a 4-digit code from K_shared for manual verification.
    /// Satisfies S1 / M2 visual safety confirmation.
    public func computeVerificationCode(derivedKey: SymmetricKey) -> String {
        // Run a simple HMAC-SHA256 of "verify" with the derived key
        let codeData = "verify".data(using: .utf8)!
        let hmac = HMAC<SHA256>.authenticationCode(for: codeData, using: derivedKey)
        
        // Map HMAC bytes to a stable 4-digit numeric code
        let hashBytes = Array(hmac)
        let number = (Int(hashBytes[0]) << 24) | (Int(hashBytes[1]) << 16) | (Int(hashBytes[2]) << 8) | Int(hashBytes[3])
        let code = abs(number) % 10000
        return String(format: "%04d", code)
    }
}

// --- Data Hex Extensions ---

extension Data {
    public init?(hexString: String) {
        let filterString = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filterString.count % 2 == 0 else { return nil }
        
        let len = filterString.count / 2
        var data = Data(capacity: len)
        var index = filterString.startIndex
        for _ in 0..<len {
            let nextIndex = filterString.index(index, offsetBy: 2)
            let byteString = filterString[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
    
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
