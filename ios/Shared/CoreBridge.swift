import Foundation

final class CoreResultCallback {
    private let handler: (String?) -> Void

    init(handler: @escaping (String?) -> Void) {
        self.handler = handler
    }

    fileprivate func deliver(_ result: String?) {
        handler(result)
    }
}

protocol CoreTunInterface: AnyObject {
    func protect(fd: Int32)
    func resolveProcess(
        protocol proto: Int32,
        source: String,
        target: String,
        uid: Int32
    ) -> String
}

private final class CoreTunInterfaceBox {
    let interface: CoreTunInterface

    init(interface: CoreTunInterface) {
        self.interface = interface
    }
}

private func retainedPointer(_ object: AnyObject) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(object).toOpaque()
}

private func unretainedObject<T: AnyObject>(
    _ pointer: UnsafeMutableRawPointer,
    as type: T.Type
) -> T? {
    Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
}

private let releaseObjectImpl: @convention(c) (UnsafeMutableRawPointer?) -> Void = { pointer in
    guard let pointer else { return }
    Unmanaged<AnyObject>.fromOpaque(pointer).release()
}

private let freeStringImpl: @convention(c) (UnsafeMutablePointer<CChar>?) -> Void = { pointer in
    free(pointer)
}

private let resultImpl: @convention(c) (
    UnsafeMutableRawPointer?, UnsafePointer<CChar>?
) -> Void = { pointer, data in
    guard let pointer,
          let callback = unretainedObject(pointer, as: CoreResultCallback.self)
    else { return }
    callback.deliver(data.map { String(cString: $0) })
}

private let protectImpl: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void = { pointer, fd in
    guard let pointer,
          let box = unretainedObject(pointer, as: CoreTunInterfaceBox.self)
    else { return }
    box.interface.protect(fd: fd)
}

private let resolveProcessImpl: @convention(c) (
    UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32
) -> UnsafeMutablePointer<CChar>? = { pointer, proto, source, target, uid in
    guard let pointer,
          let box = unretainedObject(pointer, as: CoreTunInterfaceBox.self)
    else { return strdup("") }
    let resolved = box.interface.resolveProcess(
        protocol: proto,
        source: source.map { String(cString: $0) } ?? "",
        target: target.map { String(cString: $0) } ?? "",
        uid: uid
    )
    return strdup(resolved)
}

enum CoreBridge {
    private static let installed: Void = {
        release_object_func = releaseObjectImpl
        free_string_func = freeStringImpl
        result_func = resultImpl
        protect_func = protectImpl
        resolve_process_func = resolveProcessImpl
    }()

    static func prepare() {
        _ = installed
    }

    static func invoke(_ payload: String, completion: @escaping (String?) -> Void) {
        prepare()
        let callback = CoreResultCallback(handler: completion)
        invokeMethod(retainedPointer(callback), strdup(payload))
    }

    static func setup(
        initParams: String,
        setupParams: String,
        completion: @escaping (String?) -> Void
    ) {
        prepare()
        let callback = CoreResultCallback(handler: completion)
        quickSetup(retainedPointer(callback), strdup(initParams), strdup(setupParams))
    }

    static func updateEventListener(_ listener: ((String?) -> Void)?) {
        prepare()
        guard let listener else {
            setEventListener(nil)
            return
        }
        let callback = CoreResultCallback(handler: listener)
        setEventListener(retainedPointer(callback))
    }

    @discardableResult
    static func startTunnel(
        fd: Int32,
        interface: CoreTunInterface,
        stack: String,
        address: String,
        dns: String,
        mtu: Int32
    ) -> Bool {
        prepare()
        let box = CoreTunInterfaceBox(interface: interface)
        return startTUN(
            retainedPointer(box),
            fd,
            strdup(stack),
            strdup(address),
            strdup(dns),
            mtu
        ) != 0
    }

    static func applyMemoryLimit(_ bytes: Int64) {
        prepare()
        setMemoryLimit(bytes)
    }

    static func stopTunnel() {
        stopTun()
    }

    static func setSuspended(_ suspended: Bool) {
        suspend(suspended ? 1 : 0)
    }

    static func collectGarbage() {
        forceGC()
    }

    static func setDns(_ value: String) {
        prepare()
        updateDns(strdup(value))
    }

    static func traffic(onlyStatisticsProxy: Bool) -> String {
        takeGoString(getTraffic(onlyStatisticsProxy ? 1 : 0))
    }

    static func totalTraffic(onlyStatisticsProxy: Bool) -> String {
        takeGoString(getTotalTraffic(onlyStatisticsProxy ? 1 : 0))
    }

    private static func takeGoString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
