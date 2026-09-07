import NetworkExtension
import WidgetKit
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let ipv4Address = "172.19.0.1"
    private static let ipv4PrefixLength = 30
    private static let ipv6Address = "fdfe:dcba:9876::1"
    private static let ipv6PrefixLength = 126
    private static let ipv4Dns = "172.19.0.2"
    private static let ipv6Dns = "fdfe:dcba:9876::2"
    private static let anyIpv4 = "0.0.0.0"
    private static let tunStack = "gvisor"
    private static let memoryLimitRatio = 0.7
    private static let eventBufferLimit = 512

    private let log = Logger(subsystem: "com.follow.clash.ios", category: "tunnel")
    private let stateQueue = DispatchQueue(label: "com.follow.clash.ios.tunnel.state")
    private let trafficQueue = DispatchQueue(label: "com.follow.clash.ios.tunnel.traffic")

    private var pendingEvents: [String] = []
    private var eventWaiter: (([String]) -> Void)?
    private var eventTimeoutItem: DispatchWorkItem?
    private var startedAt: Date?
    private var tunnelRunning = false
    private var trafficTimer: DispatchSourceTimer?
    private var trafficTicks = 0
    private var onlyStatisticsProxy = false

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let initParams = SharedStore.initParams else {
            completionHandler(TunnelError.missingConfiguration("initParams"))
            return
        }
        guard let sharedStateJson = SharedStore.sharedState,
              let sharedStateData = sharedStateJson.data(using: .utf8),
              let sharedState = try? JSONDecoder().decode(
                  TunnelSharedState.self,
                  from: sharedStateData
              )
        else {
            completionHandler(TunnelError.missingConfiguration("sharedState"))
            return
        }
        guard let vpnOptions = sharedState.vpnOptions else {
            completionHandler(TunnelError.missingConfiguration("vpnOptions"))
            return
        }

        onlyStatisticsProxy = sharedState.onlyStatisticsProxy ?? false
        let setupParams = sharedState.setupParams.flatMap(encodeSetupParams) ?? "{}"

        CoreBridge.applyMemoryLimit(Self.memoryLimit())
        installEventListener()
        CoreBridge.setup(initParams: initParams, setupParams: setupParams) { [weak self] message in
            guard let self else { return }
            if let message, !message.isEmpty {
                self.log.error("Core setup failed: \(message, privacy: .public)")
                self.teardownCore()
                completionHandler(TunnelError.coreSetupFailed(message))
                return
            }
            self.applyNetworkSettings(for: vpnOptions) { error in
                if let error {
                    self.teardownCore()
                    completionHandler(error)
                    return
                }
                self.attachTun(with: vpnOptions, completionHandler: completionHandler)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        log.info("Stopping tunnel: \(reason.rawValue, privacy: .public)")
        teardownCore()
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        guard let completionHandler else { return }
        let request: TunnelRequest
        do {
            request = try TunnelCoding.decode(TunnelRequest.self, from: messageData)
        } catch {
            completionHandler(encode(.failure("Malformed tunnel request: \(error)")))
            return
        }

        switch request {
        case let .invoke(payload):
            CoreBridge.invoke(payload) { [weak self] result in
                guard let self else { return }
                completionHandler(self.encode(.success(payload: result)))
            }
        case let .pollEvents(timeoutMilliseconds):
            waitForEvents(timeoutMilliseconds: timeoutMilliseconds) { [weak self] events in
                guard let self else { return }
                completionHandler(self.encode(.events(events)))
            }
        case .runTime:
            let milliseconds = startedAt.map { Int64($0.timeIntervalSince1970 * 1000) }
            completionHandler(encode(.runTime(milliseconds)))
        case let .suspend(value):
            CoreBridge.setSuspended(value)
            completionHandler(encode(.success()))
        case let .updateDns(value):
            CoreBridge.setDns(value)
            completionHandler(encode(.success()))
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        CoreBridge.setSuspended(true)
        completionHandler()
    }

    override func wake() {
        CoreBridge.setSuspended(false)
    }

    // MARK: - Core lifecycle

    private static func memoryLimit() -> Int64 {
        let available = os_proc_available_memory()
        guard available > 0 else { return 0 }
        return Int64(Double(available) * memoryLimitRatio)
    }

    private func applyNetworkSettings(
        for options: TunnelSharedState.VpnOptions,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let settings = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: Self.ipv4Address
        )
        settings.mtu = NSNumber(value: options.mtu)

        let ipv4 = NEIPv4Settings(
            addresses: [Self.ipv4Address],
            subnetMasks: [Self.subnetMask(prefixLength: Self.ipv4PrefixLength)]
        )
        ipv4.includedRoutes = Self.ipv4Routes(from: options.routeAddress)
        settings.ipv4Settings = ipv4

        var dnsServers = [Self.ipv4Dns]
        if options.ipv6 {
            let ipv6 = NEIPv6Settings(
                addresses: [Self.ipv6Address],
                networkPrefixLengths: [NSNumber(value: Self.ipv6PrefixLength)]
            )
            ipv6.includedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6
            dnsServers.append(Self.ipv6Dns)
        }

        let dns = NEDNSSettings(servers: dnsServers)
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        if options.systemProxy {
            let proxy = NEProxySettings()
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
            proxy.httpServer = NEProxyServer(address: "127.0.0.1", port: options.port)
            proxy.httpsServer = NEProxyServer(address: "127.0.0.1", port: options.port)
            proxy.exceptionList = options.bypassDomain
            settings.proxySettings = proxy
        }

        setTunnelNetworkSettings(settings, completionHandler: completionHandler)
    }

    private func attachTun(
        with options: TunnelSharedState.VpnOptions,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let fd = TunnelFileDescriptor.find(carrying: Self.ipv4Address) else {
            teardownCore()
            completionHandler(TunnelError.tunDescriptorUnavailable)
            return
        }

        let address = options.ipv6
            ? "\(Self.ipv4Address)/\(Self.ipv4PrefixLength),"
                + "\(Self.ipv6Address)/\(Self.ipv6PrefixLength)"
            : "\(Self.ipv4Address)/\(Self.ipv4PrefixLength)"
        let dns = Self.tunDns(for: options)

        let started = CoreBridge.startTunnel(
            fd: fd,
            interface: self,
            stack: Self.tunStack,
            address: address,
            dns: dns,
            mtu: Int32(options.mtu)
        )
        guard started else {
            teardownCore()
            completionHandler(TunnelError.tunStartFailed)
            return
        }

        stateQueue.sync { startedAt = Date() }
        tunnelRunning = true
        startTrafficPublishing()
        log.info("Tunnel attached on fd \(fd, privacy: .public)")
        completionHandler(nil)
    }

    private func startTrafficPublishing() {
        stopTrafficPublishing()
        let timer = DispatchSource.makeTimerSource(queue: trafficQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(30))
        timer.setEventHandler { [weak self] in
            self?.publishTraffic()
        }
        timer.resume()
        trafficTimer = timer
    }

    private func stopTrafficPublishing() {
        trafficTimer?.cancel()
        trafficTimer = nil
        trafficTicks = 0
    }

    private func publishTraffic() {
        let raw = CoreBridge.totalTraffic(onlyStatisticsProxy: onlyStatisticsProxy)
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let up = (object["up"] as? NSNumber)?.int64Value ?? 0
        let down = (object["down"] as? NSNumber)?.int64Value ?? 0
        WidgetStore.publishTraffic(upload: up, download: down)
        trafficTicks += 1
        if trafficTicks % 10 == 1 {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func teardownCore() {
        stopTrafficPublishing()
        if tunnelRunning {
            CoreBridge.stopTunnel()
            tunnelRunning = false
        }
        CoreBridge.updateEventListener(nil)
        stateQueue.sync {
            startedAt = nil
            pendingEvents.removeAll()
            eventTimeoutItem?.cancel()
            eventTimeoutItem = nil
            let waiter = eventWaiter
            eventWaiter = nil
            waiter?([])
        }
    }

    // MARK: - Events

    private func installEventListener() {
        CoreBridge.updateEventListener { [weak self] message in
            guard let self, let message else { return }
            self.enqueue(event: message)
        }
    }

    private func enqueue(event: String) {
        stateQueue.async {
            if let waiter = self.eventWaiter {
                self.eventWaiter = nil
                self.eventTimeoutItem?.cancel()
                self.eventTimeoutItem = nil
                let batch = self.pendingEvents + [event]
                self.pendingEvents.removeAll()
                waiter(batch)
                return
            }
            self.pendingEvents.append(event)
            if self.pendingEvents.count > Self.eventBufferLimit {
                self.pendingEvents.removeFirst(
                    self.pendingEvents.count - Self.eventBufferLimit
                )
            }
        }
    }

    private func waitForEvents(
        timeoutMilliseconds: Int,
        completion: @escaping ([String]) -> Void
    ) {
        stateQueue.async {
            if !self.pendingEvents.isEmpty {
                let batch = self.pendingEvents
                self.pendingEvents.removeAll()
                completion(batch)
                return
            }
            if let previous = self.eventWaiter {
                self.eventWaiter = nil
                self.eventTimeoutItem?.cancel()
                self.eventTimeoutItem = nil
                previous([])
            }
            self.eventWaiter = completion
            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let waiter = self.eventWaiter else { return }
                self.eventWaiter = nil
                self.eventTimeoutItem = nil
                let batch = self.pendingEvents
                self.pendingEvents.removeAll()
                waiter(batch)
            }
            self.eventTimeoutItem = timeout
            self.stateQueue.asyncAfter(
                deadline: .now() + .milliseconds(max(timeoutMilliseconds, 0)),
                execute: timeout
            )
        }
    }

    private func encode(_ response: TunnelResponse) -> Data? {
        try? TunnelCoding.encode(response)
    }

    private func encodeSetupParams(_ params: TunnelSharedState.SetupParams) -> String? {
        let payload: [String: Any] = [
            "selected-map": params.selectedMap,
            "test-url": params.testUrl,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func subnetMask(prefixLength: Int) -> String {
        let mask = prefixLength == 0 ? 0 : (UInt32.max << (32 - UInt32(prefixLength)))
        return [24, 16, 8, 0]
            .map { String((mask >> UInt32($0)) & 0xFF) }
            .joined(separator: ".")
    }

    private static func ipv4Routes(from routeAddress: [String]) -> [NEIPv4Route] {
        let routes = routeAddress.compactMap { entry -> NEIPv4Route? in
            let parts = entry.split(separator: "/")
            guard parts.count == 2,
                  let prefixLength = Int(parts[1]),
                  (0...32).contains(prefixLength),
                  parts[0].contains(".")
            else { return nil }
            return NEIPv4Route(
                destinationAddress: String(parts[0]),
                subnetMask: subnetMask(prefixLength: prefixLength)
            )
        }
        return routes.isEmpty ? [NEIPv4Route.default()] : routes
    }

    private static func tunDns(for options: TunnelSharedState.VpnOptions) -> String {
        if options.dnsHijacking {
            return anyIpv4
        }
        return options.ipv6 ? "\(ipv4Dns),\(ipv6Dns)" : ipv4Dns
    }
}

// MARK: - CoreTunInterface

extension PacketTunnelProvider: CoreTunInterface {
    func protect(fd: Int32) {}

    func resolveProcess(
        protocol proto: Int32,
        source: String,
        target: String,
        uid: Int32
    ) -> String {
        ""
    }
}

enum TunnelError: LocalizedError {
    case missingConfiguration(String)
    case coreSetupFailed(String)
    case tunDescriptorUnavailable
    case tunStartFailed

    var errorDescription: String? {
        switch self {
        case let .missingConfiguration(name):
            return "Missing shared configuration: \(name)"
        case let .coreSetupFailed(message):
            return "Core setup failed: \(message)"
        case .tunDescriptorUnavailable:
            return "Could not locate the utun descriptor for this tunnel"
        case .tunStartFailed:
            return "Core rejected the TUN descriptor"
        }
    }
}
