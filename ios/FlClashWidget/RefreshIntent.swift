import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh FlClash"
    static var description = IntentDescription("Fetch the latest tunnel state.")
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
