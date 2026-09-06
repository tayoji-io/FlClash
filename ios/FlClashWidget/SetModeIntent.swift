import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct SetModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set FlClash mode"
    static var description = IntentDescription("Switch the FlClash outbound mode.")
    static var openAppWhenRun = false

    @Parameter(title: "Mode")
    var mode: String

    init() {}

    init(mode: String) {
        self.mode = mode
    }

    func perform() async throws -> some IntentResult {
        try await TunnelBridge.setMode(mode)
        let previous = WidgetStore.read()
        WidgetStore.publish(
            running: previous.running,
            profileName: previous.profileName,
                proxyName: previous.proxyName,
            mode: mode
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
