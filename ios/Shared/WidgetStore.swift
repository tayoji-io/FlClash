import Foundation

struct WidgetSnapshot {
    var running: Bool
    var profileName: String
    var proxyName: String
    var mode: String
    var uploadTotal: Int64
    var downloadTotal: Int64
    var updatedAt: Date?

    static let placeholder = WidgetSnapshot(
        running: false,
        profileName: "FlClash",
        proxyName: "",
        mode: "rule",
        uploadTotal: 0,
        downloadTotal: 0,
        updatedAt: nil
    )
}

enum WidgetStore {
    private enum Key {
        static let running = "flclash.widget.running"
        static let profileName = "flclash.widget.profileName"
        static let proxyName = "flclash.widget.proxyName"
        static let mode = "flclash.widget.mode"
        static let uploadTotal = "flclash.widget.uploadTotal"
        static let downloadTotal = "flclash.widget.downloadTotal"
        static let updatedAt = "flclash.widget.updatedAt"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: CoreIdentifiers.appGroup)
    }

    static func publish(
        running: Bool,
        profileName: String,
        proxyName: String,
        mode: String
    ) {
        guard let defaults else { return }
        defaults.set(running, forKey: Key.running)
        defaults.set(profileName, forKey: Key.profileName)
        defaults.set(proxyName, forKey: Key.proxyName)
        defaults.set(mode, forKey: Key.mode)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func publishTraffic(upload: Int64, download: Int64) {
        guard let defaults else { return }
        defaults.set(upload, forKey: Key.uploadTotal)
        defaults.set(download, forKey: Key.downloadTotal)
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
            proxyName: defaults.string(forKey: Key.proxyName) ?? "",
            mode: mode.isEmpty ? "rule" : mode,
            uploadTotal: Int64(defaults.integer(forKey: Key.uploadTotal)),
            downloadTotal: Int64(defaults.integer(forKey: Key.downloadTotal)),
            updatedAt: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        )
    }
}
