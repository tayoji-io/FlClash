import Foundation
import NetworkExtension

enum TunnelBridgeError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The FlClash VPN configuration is not installed"
        }
    }
}

enum TunnelBridge {
    private static func manager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let match = managers.first { manager in
            let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
            return proto?.providerBundleIdentifier == CoreIdentifiers.tunnelBundleIdentifier
        }
        guard let match, match.isEnabled else { throw TunnelBridgeError.notInstalled }
        return match
    }

    static func isRunning() async -> Bool {
        guard let manager = try? await manager() else { return false }
        return manager.connection.status == .connected
            || manager.connection.status == .connecting
    }

    @discardableResult
    static func toggleTo(_ running: Bool) async throws -> Bool {
        let manager = try await manager()
        let active = manager.connection.status == .connected
            || manager.connection.status == .connecting
            || manager.connection.status == .reasserting
        if running == active { return active }
        return try await toggle()
    }

    @discardableResult
    static func toggle() async throws -> Bool {
        let manager = try await manager()
        switch manager.connection.status {
        case .connected, .connecting, .reasserting:
            manager.connection.stopVPNTunnel()
            return false
        default:
            guard SharedStore.initParams != nil, SharedStore.sharedState != nil else {
                throw TunnelBridgeError.notInstalled
            }
            try manager.connection.startVPNTunnel()
            return true
        }
    }
}
