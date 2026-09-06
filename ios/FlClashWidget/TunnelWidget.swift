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

    var body: some View {
        Text(mode.label)
            .font(.caption2)
            .fontWeight(isCurrent ? .semibold : .regular)
            .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
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
    let canSwitchInPlace: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TunnelMode.allCases, id: \.rawValue) { mode in
                let label = ModeLabel(mode: mode, isCurrent: mode.rawValue == current)
                if canSwitchInPlace, #available(iOS 17.0, *) {
                    Button(intent: SetModeIntent(mode: mode.rawValue)) { label }
                        .buttonStyle(.plain)
                } else {
                    Link(destination: mode.url) { label }
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

struct TunnelToggle: View {
    let running: Bool

    var body: some View {
        Capsule()
            .fill(running ? Color.green : Color.secondary.opacity(0.35))
            .frame(width: 52)
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
            TrafficRow(
                upload: entry.snapshot.uploadTotal,
                download: entry.snapshot.downloadTotal
            )
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ModeRow(
                    current: entry.snapshot.mode,
                    canSwitchInPlace: entry.snapshot.running
                )
                if #available(iOS 17.0, *) {
                    Button(intent: ToggleTunnelIntent()) {
                        TunnelToggle(running: entry.snapshot.running)
                    }
                    .buttonStyle(.plain)
                } else {
                    TunnelToggle(running: entry.snapshot.running)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .containerBackgroundIfAvailable()
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
