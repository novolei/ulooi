import SwiftUI

struct LogsView: View {
    // Plain `let` is sufficient — we only read `log.entries`, never need `$log.xxx`
    // bindings. `@Bindable` is for two-way property bindings; using it here was
    // unnecessary and may have contributed to broken observation propagation.
    let log: ProbeLog

    @State private var filter: ProbeLog.Level?
    @State private var showShare: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filtered) { entry in
                                LogRow(entry: entry).id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: log.entries.count) { _, _ in
                        if let last = filtered.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Copy all to clipboard") {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = log.export()
                            #endif
                            log.info("[meta] log exported to clipboard")
                        }
                        Button("Clear", role: .destructive) {
                            log.clear()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            FilterChip(label: "ALL", isActive: filter == nil) { filter = nil }
            ForEach(ProbeLog.Level.allCases, id: \.self) { level in
                FilterChip(label: level.rawValue, isActive: filter == level) { filter = level }
            }
            Spacer()
            Text("\(filtered.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var filtered: [ProbeLog.Entry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.level == filter }
    }
}

private struct FilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
    }
}

private struct LogRow: View {
    let entry: ProbeLog.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(timeFormat.string(from: entry.timestamp))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(entry.level.rawValue)
                .font(.caption2.monospaced().bold())
                .foregroundStyle(color)
                .frame(width: 32, alignment: .leading)
            Text(entry.message)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
        }
    }

    private var color: Color {
        switch entry.level {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        case .bytes: return .blue
        }
    }

    private var timeFormat: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }
}

#Preview {
    LogsView(log: ProbeLog.shared)
}
