import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct ToggleTunnelIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle FlClash"
    static var description = IntentDescription("Start or stop the FlClash tunnel.")
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        do {
            let running = try await TunnelBridge.toggle()
            let previous = WidgetStore.read()
            WidgetStore.publish(
                running: running,
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
