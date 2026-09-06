import Foundation
import NetworkExtension

enum TunnelManagerError: LocalizedError {
    case notInstalled
    case notConnected
    case emptyResponse
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The FlClash VPN configuration is not installed"
        case .notConnected:
            return "The FlClash tunnel is not running"
        case .emptyResponse:
            return "The tunnel returned an empty response"
        case let .remote(message):
            return message
        }
    }
}

actor TunnelManager {
    static let shared = TunnelManager()

    private var manager: NETunnelProviderManager?

    var isConnected: Bool {
        guard let status = manager?.connection.status else { return false }
        return status == .connected
    }

    var status: NEVPNStatus {
        manager?.connection.status ?? .invalid
    }

    @discardableResult
    func load() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        manager = managers.first { manager in
            let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
            return proto?.providerBundleIdentifier == CoreIdentifiers.tunnelBundleIdentifier
        }
        return manager
    }

    func install() async throws {
        let existing = try await load()
        let manager = existing ?? NETunnelProviderManager()
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol)
            ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = CoreIdentifiers.tunnelBundleIdentifier
        proto.serverAddress = "FlClash"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "FlClash"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        self.manager = manager
    }

    func start() async throws {
        if manager == nil {
            try await install()
        }
        guard let manager else { throw TunnelManagerError.notInstalled }
        if manager.connection.status == .connected
            || manager.connection.status == .connecting {
            return
        }
        if !manager.isEnabled {
            try await install()
        }
        try manager.connection.startVPNTunnel()
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    func lastDisconnectError() async -> String? {
        guard #available(iOS 16.0, *) else { return nil }
        guard let connection = manager?.connection else { return nil }
        return await withCheckedContinuation { continuation in
            connection.fetchLastDisconnectError { error in
                guard let error = error as NSError? else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: "\(error.domain)(\(error.code)) \(error.localizedDescription)"
                )
            }
        }
    }

    func send(_ request: TunnelRequest) async throws -> TunnelResponse {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            throw TunnelManagerError.notConnected
        }
        guard session.status == .connected else {
            throw TunnelManagerError.notConnected
        }
        let payload = try TunnelCoding.encode(request)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(payload) { response in
                    guard let response else {
                        continuation.resume(throwing: TunnelManagerError.emptyResponse)
                        return
                    }
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let response = try TunnelCoding.decode(TunnelResponse.self, from: data)
        if let error = response.error {
            throw TunnelManagerError.remote(error)
        }
        return response
    }
}
