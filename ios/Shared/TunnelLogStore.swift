import Foundation

enum TunnelLogStore {
    private static let fileName = "tunnel-core.log"
    private static let sizeLimit: UInt64 = 512 * 1024
    private static let queue = DispatchQueue(label: "com.follow.clash.ios.tunnel.log")

    private static var fileURL: URL {
        CoreIdentifiers.sharedContainerURL.appendingPathComponent(fileName)
    }

    static func append(_ payload: String) {
        queue.async {
            guard let data = (payload + "\n").data(using: .utf8) else { return }
            let url = fileURL
            let manager = FileManager.default
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            if size > sizeLimit {
                try? handle.truncate(atOffset: 0)
            }
            try? handle.write(contentsOf: data)
        }
    }

    static func drain() -> [String] {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return [] }
        try? Data().write(to: url)
        return text.split(separator: "\n").map(String.init)
    }
}
