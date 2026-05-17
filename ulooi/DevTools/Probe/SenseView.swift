import CoreBluetooth
import SwiftUI

struct SenseView: View {
    let central: BLECentral
    let log: ProbeLog

    @State private var subscribedCharacteristicIDs: Set<CBUUID> = []
    @State private var annotation: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Notify-able characteristics") {
                    if notifyCharacteristics.isEmpty {
                        Text("Connect + discover services first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(notifyCharacteristics, id: \.uuid) { c in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(c.uuid.uuidString).font(.caption.monospaced())
                                    if let service = c.service {
                                        Text("svc \(service.uuid.uuidString)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Toggle("", isOn: bindingForSubscription(c))
                            }
                        }
                    }
                }

                Section("Annotate event") {
                    TextField("e.g. 'I touched the head now'", text: $annotation)
                    Button("Mark in log") {
                        DevLog.event("== EVENT == \(annotation)", channel: DevLog.ui)
                        annotation = ""
                    }
                    .disabled(annotation.isEmpty)
                }

                Section("Tip") {
                    Text("Subscribe to a characteristic, then interact with the robot (touch / shake / press). Notify events appear in the Logs tab as RAW lines with characteristic UUID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sense")
        }
    }

    private var notifyCharacteristics: [CBCharacteristic] {
        central.discoveredServices.flatMap { $0.characteristics ?? [] }.filter {
            let props = CharacteristicProperties(rawValue: $0.properties.rawValue)
            return props.contains(.notify)
        }
    }

    private func bindingForSubscription(_ c: CBCharacteristic) -> Binding<Bool> {
        Binding(
            get: { subscribedCharacteristicIDs.contains(c.uuid) },
            set: { on in
                if on {
                    central.subscribe(to: c)
                    subscribedCharacteristicIDs.insert(c.uuid)
                } else {
                    central.unsubscribe(from: c)
                    subscribedCharacteristicIDs.remove(c.uuid)
                }
            }
        )
    }
}

#Preview {
    SenseView(central: BLECentral.shared, log: ProbeLog.shared)
}
