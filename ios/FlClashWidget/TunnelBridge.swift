import Foundation
import NetworkExtension

enum TunnelBridgeError: LocalizedError {
    case notInstalled
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The FlClash VPN configuration is not installed"
        case .notConnected:
            return "The FlClash tunnel is not running"
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

    static func liveTotalTraffic(onlyStatisticsProxy: Bool) async -> (Int64, Int64)? {
        guard let manager = try? await manager(),
              let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected
        else { return nil }
        let call: [String: Any] = [
            "id": UUID().uuidString,
            "method": "getTotalTraffic",
            "arguments": onlyStatisticsProxy,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: call),
              let text = String(data: body, encoding: .utf8),
              let request = try? TunnelCoding.encode(TunnelRequest.invoke(payload: text))
        else { return nil }
        let reply: Data? = await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(request) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(returning: nil)
            }
        }
        guard let reply,
              let response = try? TunnelCoding.decode(TunnelResponse.self, from: reply),
              let payload = response.payload,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any]
        else { return nil }
        let up = (result["up"] as? NSNumber)?.int64Value ?? 0
        let down = (result["down"] as? NSNumber)?.int64Value ?? 0
        return (up, down)
    }

    static func setMode(_ mode: String) async throws {
        let manager = try await manager()
        guard let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected
        else { throw TunnelBridgeError.notConnected }
        let call: [String: Any] = [
            "id": UUID().uuidString,
            "method": "updateConfig",
            "arguments": ["mode": mode],
        ]
        let payload = try JSONSerialization.data(withJSONObject: call)
        guard let text = String(data: payload, encoding: .utf8) else {
            throw TunnelBridgeError.notConnected
        }
        let request = try TunnelCoding.encode(TunnelRequest.invoke(payload: text))
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            do {
                try session.sendProviderMessage(request) { _ in c.resume() }
            } catch {
                c.resume(throwing: error)
            }
        }
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
