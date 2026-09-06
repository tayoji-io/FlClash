import Foundation
import NetworkExtension
import os

enum TunnelFileDescriptor {
    private static let log = Logger(subsystem: "com.follow.clash.ios", category: "tunnel")
    private static let sysProtoControl: Int32 = 2
    private static let utunOptionInterfaceName: Int32 = 2
    private static let scanCeiling: Int32 = 8192

    static func find(packetFlow: NEPacketTunnelFlow?) -> Int32? {
        if let fd = fromPacketFlow(packetFlow) {
            log.info("Tun descriptor \(fd, privacy: .public) resolved from packetFlow")
            return fd
        }

        let limit = descriptorLimit()
        let candidates = controlSockets(limit: limit)
        let summary = candidates.isEmpty
            ? "none"
            : candidates.map { "\($0.fd):\($0.name)" }.joined(separator: ",")

        if let match = candidates.first(where: { $0.name.hasPrefix("utun") }) {
            log.info(
                "Tun descriptor \(match.fd, privacy: .public) named \(match.name, privacy: .public) resolved by scan; candidates=\(summary, privacy: .public)"
            )
            return match.fd
        }

        log.error(
            "No utun descriptor in \(limit, privacy: .public) slots; candidates=\(summary, privacy: .public)"
        )
        return nil
    }

    private static func fromPacketFlow(_ flow: NEPacketTunnelFlow?) -> Int32? {
        guard let value = flow?.value(forKeyPath: "socket.fileDescriptor") as? NSNumber else {
            return nil
        }
        let fd = value.int32Value
        return fd >= 0 ? fd : nil
    }

    private static func controlSockets(limit: Int32) -> [(fd: Int32, name: String)] {
        var found: [(fd: Int32, name: String)] = []
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd in 0..<limit {
            var length = socklen_t(name.count)
            let result = getsockopt(
                fd,
                sysProtoControl,
                utunOptionInterfaceName,
                &name,
                &length
            )
            guard result == 0 else { continue }
            found.append((fd, String(cString: name)))
        }
        return found
    }

    private static func descriptorLimit() -> Int32 {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return 1024 }
        guard limit.rlim_cur < rlim_t(Int32.max) else { return 1024 }
        return min(max(Int32(limit.rlim_cur), 1024), scanCeiling)
    }
}
