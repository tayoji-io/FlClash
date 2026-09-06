import Foundation

struct WidgetSnapshot {
    var running: Bool
    var profileName: String
    var mode: String
    var updatedAt: Date?

    static let placeholder = WidgetSnapshot(
        running: false,
        profileName: "FlClash",
        mode: "rule",
        updatedAt: nil
    )
}

enum WidgetStore {
    private enum Key {
        static let running = "flclash.widget.running"
        static let profileName = "flclash.widget.profileName"
        static let mode = "flclash.widget.mode"
        static let updatedAt = "flclash.widget.updatedAt"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: CoreIdentifiers.appGroup)
    }

    static func publish(running: Bool, profileName: String, mode: String) {
        guard let defaults else { return }
        defaults.set(running, forKey: Key.running)
        defaults.set(profileName, forKey: Key.profileName)
        defaults.set(mode, forKey: Key.mode)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func read() -> WidgetSnapshot {
        guard let defaults else { return .placeholder }
        let name = defaults.string(forKey: Key.profileName) ?? ""
        let stamp = defaults.double(forKey: Key.updatedAt)
        let mode = defaults.string(forKey: Key.mode) ?? ""
        return WidgetSnapshot(
            running: defaults.bool(forKey: Key.running),
            profileName: name.isEmpty ? "FlClash" : name,
            mode: mode.isEmpty ? "rule" : mode,
            updatedAt: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        )
    }
}
