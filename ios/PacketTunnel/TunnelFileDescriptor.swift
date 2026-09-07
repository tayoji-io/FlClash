import Foundation
import os

enum TunnelFileDescriptor {
    private static let log = Logger(subsystem: "com.follow.clash.ios", category: "tunnel")
    private static let sysProtoControl: Int32 = 2
    private static let utunOptionInterfaceName: Int32 = 2
    private static let scanCeiling: Int32 = 8192

    static func find(carrying address: String) -> Int32? {
        let candidates = controlSockets(limit: descriptorLimit())
        let owners = interfaces(carrying: address)
        let summary = "tun descriptors="
            + (candidates.isEmpty
                ? "none"
                : candidates.map { "\($0.fd):\($0.name)" }.joined(separator: ","))
            + " \(address)="
            + (owners.isEmpty ? "unassigned" : owners.joined(separator: ","))

        guard let match = candidates.first(where: { owners.contains($0.name) })
            ?? candidates.first
        else {
            log.error("\(summary, privacy: .public)")
            return nil
        }
        log.info("\(summary, privacy: .public)")
        return match.fd
    }

    private static func interfaces(carrying address: String) -> [String] {
        var names: [String] = []
        withInterfaces { entry in
            guard let socketAddress = entry.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET)
            else { return }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let resolved = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard resolved == 0, String(cString: host) == address else { return }
            names.append(String(cString: entry.pointee.ifa_name))
        }
        return names
    }

    private static func withInterfaces(_ body: (UnsafeMutablePointer<ifaddrs>) -> Void) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            body(current)
            cursor = current.pointee.ifa_next
        }
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
