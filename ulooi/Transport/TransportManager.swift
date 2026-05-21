import Foundation
import Network
import Combine

/// Connection state of the P2P transport.
public enum TransportConnectionState: String, Sendable, Codable, Equatable {
    case disconnected = "Disconnected"
    case scanning = "Scanning"
    case connecting = "Connecting"
    case handshaking = "Handshaking"
    case connected = "Connected"
}

/// Represents a discovered UCLAW server on the local network.
public struct DiscoveredServer: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let host: String
    public let port: Int
    
    public init(name: String, host: String, port: Int) {
        self.name = name
        self.host = host
        self.port = port
    }
}

/// Manages Bonjour scanning and local WebSocket connections.
/// Implements Swift 6 concurrency guidelines and MainActor isolation for UI-safe state binding.
@MainActor
@Observable
public final class TransportManager: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    
    public static let shared = TransportManager()
    
    // --- Published States ---
    public private(set) var discoveredServers: [DiscoveredServer] = []
    public private(set) var isScanning = false
    public private(set) var connectionState: TransportConnectionState = .disconnected
    public private(set) var activeServerName: String? = nil
    public private(set) var roundTripTimeMs: Double? = nil
    
    /// Flag enabling in-memory simulation mode bypassing real raw TCP sockets.
    public var isSimulatorMode = false
    
    // --- Message Receivers ---
    private var envelopeHandlers: [@Sendable (WireEnvelope) -> Void] = []
    
    // --- Internal Properties ---
    private let serviceBrowser = NetServiceBrowser()
    private var discoveredServices: [NetService] = []
    private var webSocketTask: URLSessionWebSocketTask? = nil
    private var pingTimer: Timer? = nil
    private var activeURL: URL? = nil
    private var lastPingId: String? = nil
    private var lastPingTime: Date? = nil
    private var isReconnecting = false
    private var reconnectAttempt = 0
    private let urlSession = URLSession(configuration: .default)
    
    private override init() {
        super.init()
        serviceBrowser.delegate = self
    }
    
    // --- Scan Control ---
    
    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        connectionState = .scanning
        discoveredServers.removeAll()
        discoveredServices.removeAll()
        serviceBrowser.searchForServices(ofType: "_uclaw-bridge._tcp", inDomain: "local.")
    }
    
    public func stopScanning() {
        guard isScanning else { return }
        serviceBrowser.stop()
        isScanning = false
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }
    
    // --- Connection Control ---
    
    public func connect(to server: DiscoveredServer) {
        let wsScheme = "ws"
        // Strip trailing period from bonjour hostnames if present
        var sanitizedHost = server.host
        if sanitizedHost.hasSuffix(".") {
            sanitizedHost.removeLast()
        }
        
        guard let url = URL(string: "\(wsScheme)://\(sanitizedHost):\(server.port)/ws") else {
            return
        }
        
        activeServerName = server.name
        connect(url: url)
    }
    
    public func connect(url: URL) {
        stopScanning()
        disconnect()
        
        activeURL = url
        
        if isSimulatorMode {
            activeServerName = "Local Simulator"
            connectionState = .handshaking
            startPingTimer()
            return
        }
        
        connectionState = .connecting
        
        let task = urlSession.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        
        // Begin message receiving loop
        listenForMessages()
        
        // Start Ping-Pong loop
        startPingTimer()
        
        // Update connection status after handshake is complete (initially mark handshaking)
        connectionState = .handshaking
    }
    
    public func disconnect() {
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        activeURL = nil
        activeServerName = nil
        roundTripTimeMs = nil
        connectionState = .disconnected
        isReconnecting = false
        reconnectAttempt = 0
    }
    
    public func sendEnvelope(_ envelope: WireEnvelope) {
        if isSimulatorMode {
            // Forward directly to pairing simulator in-memory
            PairingSimulator.shared.handleClientEnvelope(envelope)
            return
        }
        
        guard let task = webSocketTask, connectionState == .connected || connectionState == .handshaking else {
            return
        }
        
        do {
            let data = try JSONEncoder().encode(envelope)
            if let jsonString = String(data: data, encoding: .utf8) {
                task.send(.string(jsonString)) { error in
                    if let error = error {
                        print("❌ WebSocket Send Error: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("❌ Failed to encode WireEnvelope: \(error.localizedDescription)")
        }
    }
    
    public func mockReceiveEnvelope(_ envelope: WireEnvelope) {
        guard isSimulatorMode else { return }
        
        // Handle Ping/Pong locally first to update RTT
        if envelope.kind == "system.pong" {
            if let lastPingId = lastPingId, envelope.replyTo == lastPingId, let lastPingTime = lastPingTime {
                let rtt = Date().timeIntervalSince(lastPingTime) * 1000
                self.roundTripTimeMs = rtt
                
                // Mark connected on first successful pong
                if connectionState == .handshaking {
                    connectionState = .connected
                }
            }
        }
        
        for handler in envelopeHandlers {
            handler(envelope)
        }
    }
    
    public func registerHandler(_ handler: @escaping @Sendable (WireEnvelope) -> Void) {
        self.envelopeHandlers.append(handler)
    }
    
    // --- WebSocket Internal Logic ---
    
    private func listenForMessages() {
        guard let task = webSocketTask else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self.processIncomingData(data)
                        }
                    case .data(let data):
                        self.processIncomingData(data)
                    @unknown default:
                        break
                    }
                    // Loop again
                    self.listenForMessages()
                    
                case .failure(let error):
                    print("❌ WebSocket Receive Error: \(error.localizedDescription)")
                    self.handleConnectionFailure()
                }
            }
        }
    }
    
    private func processIncomingData(_ data: Data) {
        do {
            let envelope = try JSONDecoder().decode(WireEnvelope.self, from: data)
            
            // Handle Ping/Pong locally first to update RTT
            if envelope.kind == "system.pong" {
                if let lastPingId = lastPingId, envelope.replyTo == lastPingId, let lastPingTime = lastPingTime {
                    let rtt = Date().timeIntervalSince(lastPingTime) * 1000
                    self.roundTripTimeMs = rtt
                    
                    // Mark connected on first successful pong
                    if connectionState == .handshaking {
                        connectionState = .connected
                    }
                }
            }
            // Forward to general handlers
            for handler in envelopeHandlers {
                handler(envelope)
            }
            
        } catch {
            print("❌ Failed to decode WireEnvelope from incoming data: \(error.localizedDescription)")
        }
    }
    
    private func handleConnectionFailure() {
        guard let url = activeURL else { return }
        
        connectionState = .disconnected
        roundTripTimeMs = nil
        
        guard reconnectAttempt < 5 else {
            print("❌ WebSocket Reconnect max attempts reached.")
            disconnect()
            return
        }
        
        reconnectAttempt += 1
        let delay = pow(2.0, Double(reconnectAttempt)) // Exponential backoff: 2s, 4s, 8s, 16s...
        print("🔄 WebSocket attempting reconnect in \(delay)s... (Attempt \(reconnectAttempt))")
        
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard self.activeURL == url else { return } // Check if user changed server
            self.connect(url: url)
        }
    }
    
    // --- Ping Pong Loop ---
    
    private func startPingTimer() {
        stopPingTimer()
        
        pingTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
        lastPingId = nil
        lastPingTime = nil
    }
    
    private func sendPing() {
        let pingId = UUID().uuidString
        self.lastPingId = pingId
        self.lastPingTime = Date()
        
        let envelope = WireEnvelope(
            id: pingId,
            src: "ulooi-client",
            kind: "system.ping",
            payload: .systemPing(SystemPing())
        )
        sendEnvelope(envelope)
    }
    
    // --- NetServiceBrowserDelegate ---
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        discoveredServices.append(service)
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        discoveredServices.removeAll { $0 == service }
        updateDiscoveredServers()
    }
    
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isScanning = false
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        isScanning = false
    }
    
    // --- NetServiceDelegate ---
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        updateDiscoveredServers()
    }
    
    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("⚠️ Bonjour Resolve Failed for \(sender.name)")
    }
    
    private func updateDiscoveredServers() {
        discoveredServers = discoveredServices.compactMap { service -> DiscoveredServer? in
            guard let host = service.hostName, service.port != -1 else { return nil }
            return DiscoveredServer(name: service.name, host: host, port: service.port)
        }
    }
}
