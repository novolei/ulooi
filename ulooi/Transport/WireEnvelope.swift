import Foundation

/// Swift Codable representations mapping exactly to the CDDL Wire Envelope Schema (v1).
/// Designed for standard JSON serialization over WebSocket or local-first IPC, matching Swift 6 Sendable requirements.

public struct WireEnvelope: Codable, Sendable {
    public let v: Int
    public let id: String
    public let ts: UInt64
    public let src: String
    public let kind: String
    public let replyTo: String?
    public let payload: WirePayload
    
    enum CodingKeys: String, CodingKey {
        case v
        case id
        case ts
        case src
        case kind
        case replyTo = "reply_to"
        case payload
    }
    
    public init(
        v: Int = 1,
        id: String = UUID().uuidString,
        ts: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
        src: String,
        kind: String,
        replyTo: String? = nil,
        payload: WirePayload
    ) {
        self.v = v
        self.id = id
        self.ts = ts
        self.src = src
        self.kind = kind
        self.replyTo = replyTo
        self.payload = payload
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.v = try container.decode(Int.self, forKey: .v)
        self.id = try container.decode(String.self, forKey: .id)
        self.ts = try container.decode(UInt64.self, forKey: .ts)
        self.src = try container.decode(String.self, forKey: .src)
        let kind = try container.decode(String.self, forKey: .kind)
        self.kind = kind
        self.replyTo = try container.decodeIfPresent(String.self, forKey: .replyTo)
        
        switch kind {
        case "system.ping":
            let val = try container.decode(SystemPing.self, forKey: .payload)
            self.payload = .systemPing(val)
        case "system.pong":
            let val = try container.decode(SystemPong.self, forKey: .payload)
            self.payload = .systemPong(val)
        case "system.state_changed":
            let val = try container.decode(SystemStateChanged.self, forKey: .payload)
            self.payload = .systemStateChanged(val)
        case "pairing.request":
            let val = try container.decode(PairingRequest.self, forKey: .payload)
            self.payload = .pairingRequest(val)
        case "pairing.response":
            let val = try container.decode(PairingResponse.self, forKey: .payload)
            self.payload = .pairingResponse(val)
        case "voice.partial":
            let val = try container.decode(VoicePartial.self, forKey: .payload)
            self.payload = .voicePartial(val)
        case "voice.final":
            let val = try container.decode(VoiceFinal.self, forKey: .payload)
            self.payload = .voiceFinal(val)
        case "agent.state":
            let val = try container.decode(AgentState.self, forKey: .payload)
            self.payload = .agentState(val)
        case "agent.token":
            let val = try container.decode(AgentToken.self, forKey: .payload)
            self.payload = .agentToken(val)
        case "embodiment.touch":
            let val = try container.decode(EmbodimentTouch.self, forKey: .payload)
            self.payload = .embodimentTouch(val)
        case "embodiment.battery":
            let val = try container.decode(EmbodimentBattery.self, forKey: .payload)
            self.payload = .embodimentBattery(val)
        case "embodiment.rssi":
            let val = try container.decode(EmbodimentRssi.self, forKey: .payload)
            self.payload = .embodimentRssi(val)
        case "embodiment.cliff_event":
            let val = try container.decode(EmbodimentCliffEvent.self, forKey: .payload)
            self.payload = .embodimentCliffEvent(val)
        case "embodiment.imu_vector":
            let val = try container.decode(EmbodimentImuVector.self, forKey: .payload)
            self.payload = .embodimentImuVector(val)
        case "actuation.motion_cmd":
            let val = try container.decode(ActuationMotionCmd.self, forKey: .payload)
            self.payload = .actuationMotionCmd(val)
        case "actuation.light_cmd":
            let val = try container.decode(ActuationLightCmd.self, forKey: .payload)
            self.payload = .actuationLightCmd(val)
        case "actuation.head_cmd":
            let val = try container.decode(ActuationHeadCmd.self, forKey: .payload)
            self.payload = .actuationHeadCmd(val)
        case "actuation.gesture_cmd":
            let val = try container.decode(ActuationGestureCmd.self, forKey: .payload)
            self.payload = .actuationGestureCmd(val)
        case "tts.text_chunk":
            let val = try container.decode(TtsTextChunk.self, forKey: .payload)
            self.payload = .ttsTextChunk(val)
        case "tts.playback_progress":
            let val = try container.decode(TtsPlaybackProgress.self, forKey: .payload)
            self.payload = .ttsPlaybackProgress(val)
        default:
            self.payload = .unknown(kind: kind)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(id, forKey: .id)
        try container.encode(ts, forKey: .ts)
        try container.encode(src, forKey: .src)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)
        
        switch payload {
        case .systemPing(let val):
            try container.encode(val, forKey: .payload)
        case .systemPong(let val):
            try container.encode(val, forKey: .payload)
        case .systemStateChanged(let val):
            try container.encode(val, forKey: .payload)
        case .pairingRequest(let val):
            try container.encode(val, forKey: .payload)
        case .pairingResponse(let val):
            try container.encode(val, forKey: .payload)
        case .voicePartial(let val):
            try container.encode(val, forKey: .payload)
        case .voiceFinal(let val):
            try container.encode(val, forKey: .payload)
        case .agentState(let val):
            try container.encode(val, forKey: .payload)
        case .agentToken(let val):
            try container.encode(val, forKey: .payload)
        case .embodimentTouch(let val):
            try container.encode(val, forKey: .payload)
        case .embodimentBattery(let val):
            try container.encode(val, forKey: .payload)
        case .embodimentRssi(let val):
            try container.encode(val, forKey: .payload)
        case .embodimentCliffEvent(let val):
            try container.encode(val, forKey: .payload)
        case .embodimentImuVector(let val):
            try container.encode(val, forKey: .payload)
        case .actuationMotionCmd(let val):
            try container.encode(val, forKey: .payload)
        case .actuationLightCmd(let val):
            try container.encode(val, forKey: .payload)
        case .actuationHeadCmd(let val):
            try container.encode(val, forKey: .payload)
        case .actuationGestureCmd(let val):
            try container.encode(val, forKey: .payload)
        case .ttsTextChunk(let val):
            try container.encode(val, forKey: .payload)
        case .ttsPlaybackProgress(let val):
            try container.encode(val, forKey: .payload)
        case .unknown:
            break
        }
    }
}

public enum WirePayload: Codable, Sendable {
    case systemPing(SystemPing)
    case systemPong(SystemPong)
    case systemStateChanged(SystemStateChanged)
    case pairingRequest(PairingRequest)
    case pairingResponse(PairingResponse)
    case voicePartial(VoicePartial)
    case voiceFinal(VoiceFinal)
    case agentState(AgentState)
    case agentToken(AgentToken)
    case embodimentTouch(EmbodimentTouch)
    case embodimentBattery(EmbodimentBattery)
    case embodimentRssi(EmbodimentRssi)
    case embodimentCliffEvent(EmbodimentCliffEvent)
    case embodimentImuVector(EmbodimentImuVector)
    case actuationMotionCmd(ActuationMotionCmd)
    case actuationLightCmd(ActuationLightCmd)
    case actuationHeadCmd(ActuationHeadCmd)
    case actuationGestureCmd(ActuationGestureCmd)
    case ttsTextChunk(TtsTextChunk)
    case ttsPlaybackProgress(TtsPlaybackProgress)
    case unknown(kind: String)
    
    public init(from decoder: Decoder) throws {
        // Handled dynamically by WireEnvelope custom decoder
        self = .unknown(kind: "undecoded")
    }
    
    public func encode(to encoder: Encoder) throws {
        // Handled dynamically by WireEnvelope custom encoder
    }
}

// --- System Namespace ---

public struct SystemPing: Codable, Sendable {
    public let sessionId: String?
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
    
    public init(sessionId: String? = nil) {
        self.sessionId = sessionId
    }
}

public struct SystemPong: Codable, Sendable {
    public let sessionId: String?
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
    
    public init(sessionId: String? = nil) {
        self.sessionId = sessionId
    }
}

public struct SystemStateChanged: Codable, Sendable {
    public let oldState: String
    public let newState: String
    public let reason: String
    
    enum CodingKeys: String, CodingKey {
        case oldState = "old_state"
        case newState = "new_state"
        case reason
    }
    
    public init(oldState: String, newState: String, reason: String) {
        self.oldState = oldState
        self.newState = newState
        self.reason = reason
    }
}

// --- Pairing Namespace ---

public struct PairingRequest: Codable, Sendable {
    public let clientStaticPk: Data      // Client static Ed25519 public key (32 bytes)
    public let clientEphPk: Data         // Client ephemeral X25519 public key (32 bytes)
    public let clientName: String        // Friendly device name
    public let signature: Data           // Ed25519 signature of (clientEphPk || serverEphPk)
    
    enum CodingKeys: String, CodingKey {
        case clientStaticPk = "client_static_pk"
        case clientEphPk = "client_eph_pk"
        case clientName = "client_name"
        case signature
    }
    
    public init(clientStaticPk: Data, clientEphPk: Data, clientName: String, signature: Data) {
        self.clientStaticPk = clientStaticPk
        self.clientEphPk = clientEphPk
        self.clientName = clientName
        self.signature = signature
    }
}

public struct PairingResponse: Codable, Sendable {
    public let serverStaticPk: Data      // Server static Ed25519 public key (32 bytes)
    public let tokenAuth: Data           // Secure 32-byte long-term auth token, encrypted with derived shared key
    public let signature: Data           // Ed25519 signature of (serverEphPk || clientEphPk)
    
    enum CodingKeys: String, CodingKey {
        case serverStaticPk = "server_static_pk"
        case tokenAuth = "token_auth"
        case signature
    }
    
    public init(serverStaticPk: Data, tokenAuth: Data, signature: Data) {
        self.serverStaticPk = serverStaticPk
        self.tokenAuth = tokenAuth
        self.signature = signature
    }
}

// --- Voice Namespace ---

public struct VoicePartial: Codable, Sendable {
    public let text: String
    public let seq: Int
    
    public init(text: String, seq: Int) {
        self.text = text
        self.seq = seq
    }
}

public struct VoiceFinal: Codable, Sendable {
    public let text: String
    public let speakerId: String?
    
    enum CodingKeys: String, CodingKey {
        case text
        case speakerId = "speaker_id"
    }
    
    public init(text: String, speakerId: String? = nil) {
        self.text = text
        self.speakerId = speakerId
    }
}

// --- Agent Namespace ---

public struct AgentState: Codable, Sendable {
    public let state: String             // "idle" | "thinking" | "speaking" | "listening"
    public let contextSummary: String?
    
    enum CodingKeys: String, CodingKey {
        case state
        case contextSummary = "context_summary"
    }
    
    public init(state: String, contextSummary: String? = nil) {
        self.state = state
        self.contextSummary = contextSummary
    }
}

public struct AgentToken: Codable, Sendable {
    public let token: String
    public let seq: Int
    
    public init(token: String, seq: Int) {
        self.token = token
        self.seq = seq
    }
}

// --- Embodiment Namespace (Sensors) ---

public struct EmbodimentTouch: Codable, Sendable {
    public let zone: String              // "head" | "back" | "left_side" | "right_side"
    public let state: String             // "began" | "moved" | "ended" | "cancelled"
    
    public init(zone: String, state: String) {
        self.zone = zone
        self.state = state
    }
}

public struct EmbodimentBattery: Codable, Sendable {
    public let percentage: Double        // 0.0 to 100.0
    public let isCharging: Bool
    
    enum CodingKeys: String, CodingKey {
        case percentage
        case isCharging = "is_charging"
    }
    
    public init(percentage: Double, isCharging: Bool) {
        self.percentage = percentage
        self.isCharging = isCharging
    }
}

public struct EmbodimentRssi: Codable, Sendable {
    public let dbm: Int
    
    public init(dbm: Int) {
        self.dbm = dbm
    }
}

public struct EmbodimentCliffEvent: Codable, Sendable {
    public let front: Bool
    public let left: Bool
    public let right: Bool
    
    public init(front: Bool, left: Bool, right: Bool) {
        self.front = front
        self.left = left
        self.right = right
    }
}

public struct EmbodimentImuVector: Codable, Sendable {
    public let acc: [Double]             // [x, y, z] in Gs
    public let gyro: [Double]            // [x, y, z] in deg/s
    
    public init(acc: [Double], gyro: [Double]) {
        self.acc = acc
        self.gyro = gyro
    }
}

// --- Actuation Namespace (Commands) ---

public struct ActuationMotionCmd: Codable, Sendable {
    public let speed: Double             // -1.0 to 1.0
    public let turn: Double              // -1.0 to 1.0
    
    public init(speed: Double, turn: Double) {
        self.speed = speed
        self.turn = turn
    }
}

public struct ActuationLightCmd: Codable, Sendable {
    public let mode: String              // "solid" | "pulse" | "blink" | "rainbow" | "off"
    public let rgb: [Int]                // [R, G, B] values (0-255)
    public let durationMs: Int?
    
    enum CodingKeys: String, CodingKey {
        case mode, rgb
        case durationMs = "duration_ms"
    }
    
    public init(mode: String, rgb: [Int], durationMs: Int? = nil) {
        self.mode = mode
        self.rgb = rgb
        self.durationMs = durationMs
    }
}

public struct ActuationHeadCmd: Codable, Sendable {
    public let pitch: Int                // head pitch in degrees (-15 to 15)
    
    public init(pitch: Int) {
        self.pitch = pitch
    }
}

public struct ActuationGestureCmd: Codable, Sendable {
    public let gesture: String
    
    public init(gesture: String) {
        self.gesture = gesture
    }
}

// --- TTS Namespace ---

public struct TtsTextChunk: Codable, Sendable {
    public let text: String
    public let isFinal: Bool
    
    enum CodingKeys: String, CodingKey {
        case text
        case isFinal = "is_final"
    }
    
    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public struct TtsPlaybackProgress: Codable, Sendable {
    public let playedMs: Int
    public let totalMs: Int
    
    enum CodingKeys: String, CodingKey {
        case playedMs = "played_ms"
        case totalMs = "total_ms"
    }
    
    public init(playedMs: Int, totalMs: Int) {
        self.playedMs = playedMs
        self.totalMs = totalMs
    }
}
