import LooiKit
import SwiftUI

// MARK: - DevToolsScanCoordinator

/// Drives `transport.scan(...)` into an observable discoveries list so ScanView
/// can display all peripherals (including non-Looi) for manual selection.
///
/// LooiSession's own scan auto-connects to the first match; this coordinator
/// drives the transport stream independently so the user can browse and pick.
///
/// Note: DevToolsScanCoordinator and LooiSession share the same CoreBluetooth
/// transport. Calling start() here while session.startScanAndConnect() is also
/// running is not recommended — only one scan is active at a time in practice
/// because DevTools is the UI for manual exploration, not production auto-connect.
@MainActor
@Observable
final class DevToolsScanCoordinator {
    var discoveries: [DiscoveredPeripheral] = []
    var isScanning: Bool = false
    var nameFilter: String = "LOOI"

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    private let transport: BLETransport

    init(transport: BLETransport) {
        self.transport = transport
    }

    func start() {
        guard !isScanning else { return }
        isScanning = true
        let filter = nameFilter
        scanTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.transport.scan(nameFilter: filter)
            for await p in stream {
                if Task.isCancelled { break }
                if let idx = self.discoveries.firstIndex(where: { $0.id == p.id }) {
                    self.discoveries[idx] = p
                } else {
                    self.discoveries.append(p)
                }
            }
        }
    }

    func stop() async {
        scanTask?.cancel()
        scanTask = nil
        await transport.stopScan()
        isScanning = false
    }

    func clearDiscoveries() {
        discoveries.removeAll()
    }
}

// MARK: - ScanView

struct ScanView: View {
    let transport: BLETransport
    let session: LooiSession
    let log: ProbeLog

    @State private var coordinator: DevToolsScanCoordinator

    init(transport: BLETransport, session: LooiSession, log: ProbeLog) {
        self.transport = transport
        self.session = session
        self.log = log
        _coordinator = State(initialValue: DevToolsScanCoordinator(transport: transport))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Session state") {
                    HStack {
                        Text(session.state.description.capitalized)
                            .foregroundStyle(session.state.isReady ? .green : .secondary)
                        Spacer()
                        if coordinator.isScanning {
                            ProgressView()
                        }
                    }
                }

                Section("Filter") {
                    Toggle("Only show LOOI devices", isOn: Binding(
                        get: { !coordinator.nameFilter.isEmpty },
                        set: { coordinator.nameFilter = $0 ? "LOOI" : "" }
                    ))
                    HStack {
                        Button(coordinator.isScanning ? "Stop Scan" : "Start Scan") {
                            DevLog.event(
                                "ScanView: \(coordinator.isScanning ? "Stop" : "Start") Scan tapped " +
                                "(sessionState=\(session.state.description), isScanning=\(coordinator.isScanning))",
                                channel: DevLog.ui
                            )
                            if coordinator.isScanning {
                                Task { await coordinator.stop() }
                            } else {
                                coordinator.start()
                            }
                        }
                        // Explicit buttonStyle is REQUIRED here. Without it, SwiftUI
                        // treats a multi-Button HStack inside a Form Section row as a
                        // single tap target — tapping anywhere fires ALL Buttons.
                        // See [[feedback-swiftui-form-row-buttons]].
                        .buttonStyle(.borderedProminent)
                        Spacer()
                        Button("Clear results", role: .destructive) {
                            DevLog.event("ScanView: Clear results tapped", channel: DevLog.ui)
                            Task { await coordinator.stop() }
                            coordinator.clearDiscoveries()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Discovered (\(coordinator.discoveries.count))") {
                    let items = coordinator.discoveries.sorted { $0.rssi > $1.rssi }
                    if items.isEmpty {
                        Text("No peripherals yet. Tap Start Scan.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { d in
                            DiscoveryRow(discovery: d, session: session, log: log)
                        }
                    }
                }
            }
            .navigationTitle("Scan")
        }
    }
}

// MARK: - DiscoveryRow

private struct DiscoveryRow: View {
    let discovery: DiscoveredPeripheral
    let session: LooiSession
    let log: ProbeLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(discovery.name)
                    .font(.headline)
                Spacer()
                Text("\(discovery.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(rssiColor(discovery.rssi))
            }
            Text(discovery.id.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if !discovery.advertisedServices.isEmpty {
                Text("services: \(discovery.advertisedServices.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let mfg = discovery.manufacturerData {
                Text("mfg: \(mfg.hexEncoded)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                // session.connect(to:) drives the full connect → discover →
                // handshake → ready pipeline automatically (LooiKit M1 design).
                // No separate "auto-init" step needed.
                Button("⚡ Connect via LooiSession") {
                    DevLog.event(
                        "ScanView: connect(\(discovery.name) / \(discovery.id.uuidString.prefix(8))) tapped",
                        channel: DevLog.ui
                    )
                    // Use the peripheral overload so currentPeripheral is set
                    // immediately on tap — ConnectionBanner becomes visible
                    // straight away, and CommandView enables its buttons
                    // (both observe currentPeripheral != nil).
                    session.connect(discovery)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi > -60 { return .green }
        if rssi > -80 { return .orange }
        return .red
    }
}

#Preview {
    ScanView(
        transport: LooiBootstrap.shared.transport,
        session: LooiBootstrap.shared.session,
        log: ProbeLog.shared
    )
}
