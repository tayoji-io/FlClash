import Foundation
import NetworkExtension

enum TunnelBridgeError: LocalizedError {
    case notInstalled
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The FlClash VPN configuration is not installed"
        case let .remote(message):
            return message
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

    private static func name(of status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    @discardableResult
    static func setMode(_ mode: String) async throws -> Bool {
        guard let manager = try? await manager() else { return false }
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw TunnelBridgeError.remote("The tunnel session is unavailable")
        }
        switch session.status {
        case .connected:
            break
        case .disconnected, .invalid:
            return false
        default:
            throw TunnelBridgeError.remote(
                "The tunnel is \(Self.name(of: session.status)); mode was not sent"
            )
        }
        let call: [String: Any] = [
            "id": UUID().uuidString,
            "method": "updateConfig",
            "arguments": ["mode": mode],
        ]
        let payload = try JSONSerialization.data(withJSONObject: call)
        guard let text = String(data: payload, encoding: .utf8) else {
            throw TunnelBridgeError.remote("Could not encode the mode request")
        }
        let request = try TunnelCoding.encode(TunnelRequest.invoke(payload: text))
        let reply: Data? = await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(request) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(returning: nil)
            }
        }
        guard let reply else {
            throw TunnelBridgeError.remote("The tunnel did not answer the mode request")
        }
        let response = try TunnelCoding.decode(TunnelResponse.self, from: reply)
        if let error = response.error {
            throw TunnelBridgeError.remote(error)
        }
        if let body = response.payload,
           let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let failure = object["error"] as? [String: Any] {
            throw TunnelBridgeError.remote(
                failure["message"] as? String ?? "updateConfig was rejected"
            )
        }
        return true
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
