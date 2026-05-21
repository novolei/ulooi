import Foundation
import CryptoKit
import Observation

/// A fully self-contained local simulator that runs inside the iOS app.
/// It acts as the "UCLAW Desktop" endpoint, generating mock QR codes,
/// negotiating the ECDH pairing handshake, validating signatures,
/// and streaming simulated actuation commands to verify Face and BLE behaviors.
@MainActor
@Observable
public final class PairingSimulator: @unchecked Sendable {
    
    public static let shared = PairingSimulator()
    
    // --- Simulator States ---
    public private(set) var pairingURI: String = ""
    public private(set) var computedVerificationCode: String = ""
    public private(set) var isWaitingForRequest = false
    public private(set) var handshakeCompleted = false
    public private(set) var activeSession = false
    
    // --- Cryptographic Keys ---
    private var serverStaticKey: Curve25519.Signing.PrivateKey?
    private var serverEphKey: Curve25519.KeyAgreement.PrivateKey?
    private var salt: Data?
    
    // --- Client Context Cached During Handshake ---
    private var clientStaticPublicKeyData: Data?
    private var clientEphPublicKeyData: Data?
    
    // --- Telemetry Pushes ---
    private var actuationTimer: Timer? = nil
    
    private init() {
        resetKeys()
    }
    
    /// Re-generates server static/ephemeral identities and salt, then exposes a new uclaw:// pair URI
    public func resetKeys() {
        let staticKey = Curve25519.Signing.PrivateKey()
        let ephKey = Curve25519.KeyAgreement.PrivateKey()
        
        var randomSalt = Data(count: 16)
        let status = randomSalt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        if status != errSecSuccess {
            // Fallback
            randomSalt = "ulooimockp2psalt".data(using: .utf8)!
        }
        
        self.serverStaticKey = staticKey
        self.serverEphKey = ephKey
        self.salt = randomSalt
        
        self.pairingURI = "uclaw://pair?host=UCLAW-Simulator&port=8080&pk_S_eph=\(ephKey.publicKey.rawRepresentation.hexString)&salt=\(randomSalt.hexString)&pk_S_static=\(staticKey.publicKey.rawRepresentation.hexString)"
        self.computedVerificationCode = ""
        self.isWaitingForRequest = true
        self.handshakeCompleted = false
        self.activeSession = false
        
        stopActuationStream()
    }
    
    /// Entrypoint for client packet interception when TransportManager is in Simulator mode.
    public func handleClientEnvelope(_ envelope: WireEnvelope) {
        switch envelope.kind {
        case "system.ping":
            handlePing(envelope)
        case "pairing.request":
            if case let .pairingRequest(req) = envelope.payload {
                handlePairingRequest(req, envelopeId: envelope.id)
            }
        default:
            print("🤖 Simulator received envelope \(envelope.kind) (unhandled)")
        }
    }
    
    // --- Handshake Implementation ---
    
    private func handlePairingRequest(_ req: PairingRequest, envelopeId: String) {
        guard let serverStaticKey = serverStaticKey,
              let serverEphKey = serverEphKey,
              let salt = salt else {
            return
        }
        
        do {
            let clientStaticPk = try Curve25519.Signing.PublicKey(rawRepresentation: req.clientStaticPk)
            let clientEphPk = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: req.clientEphPk)
            
            // 1. Verify Client Signature: Sign_sk_client_static(pk_C_eph || pk_S_eph)
            var signedMessage = Data()
            signedMessage.append(clientEphPk.rawRepresentation)
            signedMessage.append(serverEphKey.publicKey.rawRepresentation)
            
            guard clientStaticPk.isValidSignature(req.signature, for: signedMessage) else {
                print("❌ Simulator: Client Signature Verification Failed!")
                return
            }
            
            // Cache details
            self.clientStaticPublicKeyData = req.clientStaticPk
            self.clientEphPublicKeyData = req.clientEphPk
            
            // 2. Compute K_shared via Curve25519 ECDH + HKDF
            let sharedSecret = try serverEphKey.sharedSecretFromKeyAgreement(with: clientEphPk)
            let derivedHandshakeKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: "ulooi-pairing-v1".data(using: .utf8)!,
                outputByteCount: 32
            )
            
            // Compute 4-digit code matching the client
            self.computedVerificationCode = PairingService.shared.computeVerificationCode(derivedKey: derivedHandshakeKey)
            print("🤖 Simulator Derived Verification Code: [ \(computedVerificationCode) ]")
            
            // 3. Encrypt long-term token_auth using derivedHandshakeKey
            var rawToken = Data(count: 32)
            _ = rawToken.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
            }
            
            let sealedBox = try AES.GCM.seal(rawToken, using: derivedHandshakeKey)
            guard let combinedCipher = sealedBox.combined else {
                throw CryptoKitError.incorrectKeySize
            }
            
            // 4. Compute Server Signature: Sign_sk_server_static(pk_S_eph || pk_C_eph)
            var serverMessageToSign = Data()
            serverMessageToSign.append(serverEphKey.publicKey.rawRepresentation)
            serverMessageToSign.append(clientEphPk.rawRepresentation)
            
            let serverSignature = try serverStaticKey.signature(for: serverMessageToSign)
            
            // 5. Send Response
            let responsePayload = PairingResponse(
                serverStaticPk: serverStaticKey.publicKey.rawRepresentation,
                tokenAuth: combinedCipher,
                signature: serverSignature
            )
            
            let responseEnvelope = WireEnvelope(
                id: UUID().uuidString,
                src: "uclaw-desktop-simulator",
                kind: "pairing.response",
                replyTo: envelopeId,
                payload: .pairingResponse(responsePayload)
            )
            
            // Delay slightly to simulate network latency
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.handshakeCompleted = true
                self.activeSession = true
                TransportManager.shared.mockReceiveEnvelope(responseEnvelope)
                self.startActuationStream()
            }
            
        } catch {
            print("❌ Simulator Handshake Error: \(error.localizedDescription)")
        }
    }
    
    private func handlePing(_ envelope: WireEnvelope) {
        let pongEnvelope = WireEnvelope(
            id: UUID().uuidString,
            src: "uclaw-desktop-simulator",
            kind: "system.pong",
            replyTo: envelope.id,
            payload: .systemPong(SystemPong())
        )
        TransportManager.shared.mockReceiveEnvelope(pongEnvelope)
    }
    
    // --- Mock Inbound Actuation Commands (Desktop -> ulooi Client) ---
    
    public func triggerMockCommand(_ envelope: WireEnvelope) {
        guard activeSession else { return }
        TransportManager.shared.mockReceiveEnvelope(envelope)
    }
    
    private func startActuationStream() {
        stopActuationStream()
        
        // Every 5 seconds, send a random mock command to make the Client Face look alive!
        actuationTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.sendRandomActuation()
            }
        }
    }
    
    private func stopActuationStream() {
        actuationTimer?.invalidate()
        actuationTimer = nil
    }
    
    private func sendRandomActuation() {
        let states = ["thinking", "listening", "speaking", "idle"]
        let randomState = states.randomElement() ?? "idle"
        
        let agentState = AgentState(state: randomState, contextSummary: "Simulator running loop")
        let envelope = WireEnvelope(
            src: "uclaw-desktop-simulator",
            kind: "agent.state",
            payload: .agentState(agentState)
        )
        
        TransportManager.shared.mockReceiveEnvelope(envelope)
    }
}
