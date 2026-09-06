import Foundation

enum CoreIdentifiers {
    static let appGroup = infoValue(for: "FLClashAppGroup")
    static let tunnelBundleIdentifier = infoValue(for: "FLClashTunnelBundleIdentifier")

    static func modeURL(_ mode: String) -> URL {
        URL(string: "flclash://mode?value=\(mode)")!
    }

    static var sharedContainerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            fatalError("App Group \(appGroup) is not available to this process")
        }
        return url
    }

    private static func infoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            fatalError("Missing Info.plist entry: \(key)")
        }
        return value
    }
}
