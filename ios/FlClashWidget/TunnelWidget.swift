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
        let entry = TunnelEntry(date: Date(), snapshot: WidgetStore.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
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

struct ModeRow: View {
    let current: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TunnelMode.allCases, id: \.rawValue) { mode in
                Link(destination: mode.url) {
                    Text(mode.label)
                        .font(.caption2.weight(mode.rawValue == current ? .bold : .regular))
                        .foregroundStyle(mode.rawValue == current ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(mode.rawValue == current
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.secondary.opacity(0.08))
                        )
                }
            }
        }
    }
}

struct TunnelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TunnelEntry

    private var accent: Color { entry.snapshot.running ? .green : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.snapshot.running
                      ? "bolt.horizontal.fill" : "bolt.horizontal")
                    .foregroundStyle(accent)
                Text("FlClash")
                    .font(.headline)
                Spacer()
            }
            Text(entry.snapshot.profileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if family != .systemSmall {
                ModeRow(current: entry.snapshot.mode)
            }
            Spacer(minLength: 0)
            if #available(iOS 17.0, *) {
                Button(intent: ToggleTunnelIntent()) {
                    Text(entry.snapshot.running ? "停止" : "启动")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            } else {
                Text(entry.snapshot.running ? "运行中" : "已停止")
                    .font(.caption.bold())
                    .foregroundStyle(accent)
            }
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
