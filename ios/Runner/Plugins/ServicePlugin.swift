import Flutter
import Foundation
import NetworkExtension
import WidgetKit

public class ServicePlugin: NSObject, FlutterPlugin {
    private static let runtimeMethods: Set<String> = [
        "asyncTestDelay",
        "getTraffic",
        "getTotalTraffic",
        "resetTraffic",
        "getConnections",
        "closeConnections",
        "resetConnections",
        "closeConnection",
        "getMemory",
        "startLog",
        "stopLog",
    ]

    private static let tunnelOnlyMethods: Set<String> = [
        "startListener",
        "stopListener",
    ]

    private static let broadcastMethods: Set<String> = [
        "changeProxy",
        "updateConfig",
        "setupConfig",
        "updateGeoData",
        "sideLoadExternalProvider",
        "updateExternalProvider",
        "clearEffect",
        "forceGc",
        "updateDns",
    ]

    private static let eventPollTimeoutMilliseconds = 1000

    private let channel: FlutterMethodChannel
    private var eventPollTask: Task<Void, Never>?
    private var statusObserver: NSObjectProtocol?
    private var logRequested = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.follow.clash/service",
            binaryMessenger: registrar.messenger()
        )
        let instance = ServicePlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            initialize(result: result)
        case "shutdown":
            shutdown(result: result)
        case "invokeMethod":
            invoke(call: call, result: result)
        case "getRunTime":
            runTime(result: result)
        case "syncState":
            syncState(call: call, result: result)
        case "start":
            start(result: result)
        case "stop":
            stop(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        teardown()
    }

    private func initialize(result: @escaping FlutterResult) {
        CoreBridge.updateEventListener { [weak self] message in
            self?.send(event: message)
        }
        observeTunnelStatus()
        Task {
            _ = try? await TunnelManager.shared.load()
            await MainActor.run { result("") }
        }
    }

    private func shutdown(result: @escaping FlutterResult) {
        teardown()
        Task {
            await TunnelManager.shared.stop()
            await MainActor.run { result(true) }
        }
    }

    private func start(result: @escaping FlutterResult) {
        Task {
            do {
                try await TunnelManager.shared.start()
                await MainActor.run { result(true) }
            } catch {
                self.sendLog("tunnel start failed: \(error.localizedDescription)")
                await MainActor.run { result(false) }
            }
        }
    }

    private func stop(result: @escaping FlutterResult) {
        Task {
            await TunnelManager.shared.stop()
            await MainActor.run { result(true) }
        }
    }

    private func syncState(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let payload = call.arguments as? String else {
            result("Invalid shared state")
            return
        }
        SharedStore.sharedState = payload
        Task { self.publishWidgetState(await TunnelManager.shared.status) }
        result("")
    }

    private func runTime(result: @escaping FlutterResult) {
        Task {
            let milliseconds: Int64
            do {
                let response = try await TunnelManager.shared.send(.runTime)
                milliseconds = response.runTimeMilliseconds ?? 0
            } catch {
                milliseconds = 0
            }
            await MainActor.run { result(milliseconds) }
        }
    }

    private func invoke(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let payload = call.arguments as? String else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "Method call payload must be a string",
                    details: nil
                )
            )
            return
        }

        let method = Self.methodName(from: payload)
        if method == "startLog" {
            logRequested = true
        } else if method == "stopLog" {
            logRequested = false
        }
        if method == "initClash" {
            SharedStore.initParams = Self.argumentsJson(from: payload)
        }

        if let method, Self.tunnelOnlyMethods.contains(method) {
            Task {
                _ = try? await TunnelManager.shared.send(.invoke(payload: payload))
                let response = Self.localResponse(for: payload, result: true)
                await MainActor.run { result(response) }
            }
            return
        }

        if let method, Self.runtimeMethods.contains(method) {
            Task {
                if let response = try? await TunnelManager.shared.send(.invoke(payload: payload)),
                   let remote = response.payload {
                    await MainActor.run { result(remote) }
                    return
                }
                self.invokeLocal(payload, result: result)
            }
            return
        }

        if let method, Self.broadcastMethods.contains(method) {
            Task {
                _ = try? await TunnelManager.shared.send(.invoke(payload: payload))
            }
        }

        invokeLocal(payload, result: result)
    }

    private func invokeLocal(_ payload: String, result: @escaping FlutterResult) {
        CoreBridge.invoke(payload) { response in
            DispatchQueue.main.async { result(response) }
        }
    }

    private func publishWidgetState(_ status: NEVPNStatus) {
        let running = status == .connected || status == .connecting
        let shared = Self.decodedSharedState()
        WidgetStore.publish(
            running: running,
            profileName: shared?.currentProfileName ?? "FlClash",
            proxyName: shared?.currentProxyName ?? "",
            mode: shared?.mode ?? "rule"
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func decodedSharedState() -> TunnelSharedState? {
        guard let json = SharedStore.sharedState,
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(TunnelSharedState.self, from: data)
    }

    private func sendLog(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod("log", arguments: message)
        }
    }

    private func send(event: String?) {
        guard let event else { return }
        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod("event", arguments: event)
        }
    }

    private func observeTunnelStatus() {
        guard statusObserver == nil else { return }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshEventPolling()
            self?.logTunnelStatus()
        }
        refreshEventPolling()
        logTunnelStatus()
    }

    private func logTunnelStatus() {
        Task {
            let status = await TunnelManager.shared.status
            self.publishWidgetState(status)
            self.sendLog("tunnel status: \(Self.statusName(status))")
            guard status == .disconnected || status == .invalid else { return }
            if let message = await TunnelManager.shared.lastDisconnectError() {
                self.sendLog("tunnel last disconnect error: \(message)")
            }
        }
    }

    private static func statusName(_ status: NEVPNStatus) -> String {
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

    private func refreshEventPolling() {
        Task { [weak self] in
            guard let self else { return }
            let connected = await TunnelManager.shared.isConnected
            await MainActor.run {
                if connected {
                    self.startEventPolling()
                    self.resumeTunnelLogging()
                } else {
                    self.stopEventPolling()
                }
            }
        }
    }

    private func resumeTunnelLogging() {
        guard logRequested else { return }
        let call: [String: Any] = [
            "id": UUID().uuidString,
            "method": "startLog",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: call),
              let payload = String(data: data, encoding: .utf8)
        else { return }
        Task {
            _ = try? await TunnelManager.shared.send(.invoke(payload: payload))
        }
    }

    private func startEventPolling() {
        guard eventPollTask == nil else { return }
        eventPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let response = try await TunnelManager.shared.send(
                        .pollEvents(timeoutMilliseconds: Self.eventPollTimeoutMilliseconds)
                    )
                    for event in response.events ?? [] {
                        self.send(event: event)
                    }
                } catch {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }

    private func stopEventPolling() {
        eventPollTask?.cancel()
        eventPollTask = nil
    }

    private func teardown() {
        stopEventPolling()
        CoreBridge.updateEventListener(nil)
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
            self.statusObserver = nil
        }
    }

    private static func methodName(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["method"] as? String
    }

    private static func localResponse(for payload: String, result: Any) -> String? {
        var response: [String: Any] = ["result": result]
        if let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = object["id"] as? String {
            response["id"] = id
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: response) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }

    private static func argumentsJson(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arguments = object["arguments"],
              let encoded = try? JSONSerialization.data(withJSONObject: arguments)
        else { return nil }
        return String(data: encoded, encoding: .utf8)
    }
}
