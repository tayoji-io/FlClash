import SwiftUI
import WidgetKit

struct TunnelEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TunnelProvider: TimelineProvider {
    func placeholder(in context: Context) -> TunnelEntry {
        TunnelEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TunnelEntry) -> Void) {
        completion(TunnelEntry(date: Date(), snapshot: WidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TunnelEntry>) -> Void) {
        Task {
            var snapshot = WidgetStore.read()
            let running = await TunnelBridge.isRunning()
            if running != snapshot.running {
                snapshot.running = running
                WidgetStore.publish(
                    running: running,
                    profileName: snapshot.profileName,
                    proxyName: snapshot.proxyName,
                    mode: snapshot.mode
                )
            }
            if snapshot.running,
               let live = await TunnelBridge.liveTotalTraffic(onlyStatisticsProxy: false) {
                snapshot.uploadTotal = live.0
                snapshot.downloadTotal = live.1
                WidgetStore.publishTraffic(upload: live.0, download: live.1)
            }
            let entry = TunnelEntry(date: Date(), snapshot: snapshot)
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(Date().addingTimeInterval(300))
                )
            )
        }
    }
}

enum TunnelMode: String, CaseIterable {
    case rule
    case global
    case direct

    var label: String {
        switch self {
        case .rule: return "规则"
        case .global: return "全局"
        case .direct: return "直连"
        }
    }

    var url: URL {
        CoreIdentifiers.modeURL(rawValue)
    }
}

struct ModeLabel: View {
    let mode: TunnelMode
    let isCurrent: Bool
    var vertical = false

    var body: some View {
        Text(mode.label)
            .font(vertical ? .caption : .caption2)
            .fontWeight(isCurrent ? .semibold : .regular)
            .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            .frame(maxWidth: vertical ? nil : .infinity)
            .padding(.vertical, vertical ? 5 : 7)
            .padding(.horizontal, vertical ? 12 : 0)
            .background(
                Group {
                    if isCurrent {
                        Capsule().fill(.background.opacity(0.9))
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                    }
                }
            )
            .contentShape(Capsule())
    }
}

struct ModeRow: View {
    let current: String
    var vertical = false

    var body: some View {
        if vertical {
            VStack(alignment: .leading, spacing: 2) { items }
        } else {
            HStack(spacing: 2) { items }
                .padding(2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }

    @ViewBuilder
    private var items: some View {
        ForEach(TunnelMode.allCases, id: \.rawValue) { mode in
            let label = ModeLabel(
                mode: mode,
                isCurrent: mode.rawValue == current,
                vertical: vertical
            )
            if #available(iOS 17.0, *) {
                Button(intent: SetModeIntent(mode: mode.rawValue)) { label }
                    .buttonStyle(.plain)
            } else {
                Link(destination: mode.url) { label }
            }
        }
    }
}

struct TunnelToggle: View {
    let running: Bool
    var width: CGFloat?

    var body: some View {
        Capsule()
            .fill(running ? Color.green : Color.secondary.opacity(0.35))
            .frame(maxWidth: width ?? .infinity)
            .frame(maxHeight: .infinity)
            .overlay {
                GeometryReader { geometry in
                    let inset: CGFloat = 3
                    let diameter = max(geometry.size.height - inset * 2, 0)
                    Circle()
                        .fill(.white)
                        .shadow(radius: 0.5)
                        .frame(width: diameter, height: diameter)
                        .position(
                            x: running
                                ? geometry.size.width - diameter / 2 - inset
                                : diameter / 2 + inset,
                            y: geometry.size.height / 2
                        )
                }
            }
    }
}

struct TrafficRow: View {
    let upload: Int64
    let download: Int64

    private static let formatter: ByteCountFormatter = {
        let value = ByteCountFormatter()
        value.countStyle = .binary
        value.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return value
    }()

    private func format(_ bytes: Int64) -> String {
        Self.formatter.string(fromByteCount: max(bytes, 0))
    }

    var body: some View {
        HStack(spacing: 10) {
            Label(format(download), systemImage: "arrow.down")
            Label(format(upload), systemImage: "arrow.up")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct TunnelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TunnelEntry

    private var isCompact: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                entry.snapshot.proxyName.isEmpty
                    ? entry.snapshot.profileName
                    : entry.snapshot.proxyName
            )
            .font(.system(size: isCompact ? 15 : 17, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Text(entry.snapshot.profileName)
                    .lineLimit(1)
                Text("·")
                Text(entry.snapshot.running ? "已连接" : "未连接")
                    .foregroundStyle(entry.snapshot.running ? .green : .secondary)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if isCompact {
                HStack(alignment: .bottom, spacing: 8) {
                    modeRow
                    Spacer(minLength: 0)
                    toggleButton.frame(height: 28)
                }
            } else {
                TrafficRow(
                    upload: entry.snapshot.uploadTotal,
                    download: entry.snapshot.downloadTotal
                )
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    modeRow
                    toggleButton
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .containerBackgroundIfAvailable()
    }

    private var modeRow: ModeRow {
        ModeRow(current: entry.snapshot.mode, vertical: isCompact)
    }

    @ViewBuilder
    private var toggleButton: some View {
        let toggle = TunnelToggle(
            running: entry.snapshot.running,
            width: isCompact ? 48 : 52
        )
        if #available(iOS 17.0, *) {
            Button(intent: ToggleTunnelIntent()) { toggle }
                .buttonStyle(.plain)
        } else {
            toggle
        }
    }
}

extension View {
    @ViewBuilder
    func containerBackgroundIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self.padding()
        }
    }
}

struct TunnelWidget: Widget {
    let kind = "FlClashTunnelWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TunnelProvider()) { entry in
            TunnelWidgetView(entry: entry)
        }
        .configurationDisplayName("FlClash")
        .description("查看状态、切换模式与启停隧道。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
