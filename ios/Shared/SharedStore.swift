import Foundation

enum SharedStore {
    private enum Key {
        static let initParams = "flclash.initParams"
        static let sharedState = "flclash.sharedState"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: CoreIdentifiers.appGroup)
    }

    static var initParams: String? {
        get { defaults?.string(forKey: Key.initParams) }
        set { defaults?.set(newValue, forKey: Key.initParams) }
    }

    static var sharedState: String? {
        get { defaults?.string(forKey: Key.sharedState) }
        set { defaults?.set(newValue, forKey: Key.sharedState) }
    }
}

struct TunnelSharedState: Decodable {
    struct SetupParams: Decodable {
        var selectedMap: [String: String]
        var testUrl: String

        private enum CodingKeys: String, CodingKey {
            case selectedMap = "selected-map"
            case testUrl = "test-url"
        }
    }

    struct VpnOptions: Decodable {
        var enable: Bool
        var port: Int
        var ipv6: Bool
        var dnsHijacking: Bool
        var allowBypass: Bool
        var systemProxy: Bool
        var bypassDomain: [String]
        var stack: String
        var mtu: Int
        var routeAddress: [String]
    }

    var setupParams: SetupParams?
    var vpnOptions: VpnOptions?
    var currentProfileName: String?
    var currentProxyName: String?
    var mode: String?
    var onlyStatisticsProxy: Bool?
}
