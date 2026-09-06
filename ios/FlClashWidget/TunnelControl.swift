import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct TunnelControlValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        await TunnelBridge.isRunning()
    }
}

@available(iOS 18.0, *)
struct SetTunnelIntent: SetValueIntent {
    static var title: LocalizedStringResource = "FlClash"

    @Parameter(title: "Running")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        do {
            if value {
                _ = try await TunnelBridge.toggleTo(true)
            } else {
                _ = try await TunnelBridge.toggleTo(false)
            }
            let previous = WidgetStore.read()
            WidgetStore.publish(
                running: value,
                profileName: previous.profileName,
                proxyName: previous.proxyName,
                mode: previous.mode
            )
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        } catch {
            throw error
        }
    }
}

@available(iOS 18.0, *)
struct TunnelControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.follow.clash.ios.control.tunnel",
            provider: TunnelControlValueProvider()
        ) { isRunning in
            ControlWidgetToggle(
                "FlClash",
                isOn: isRunning,
                action: SetTunnelIntent()
            ) { running in
                Label(running ? "已连接" : "未连接", systemImage: "bolt.horizontal.fill")
            }
        }
        .displayName("FlClash")
        .description("切换 FlClash 隧道。")
    }
}
