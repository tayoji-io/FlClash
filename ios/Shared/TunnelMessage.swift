import Foundation

enum TunnelRequest: Codable {
    case invoke(payload: String)
    case pollEvents(timeoutMilliseconds: Int)
    case runTime
    case suspend(value: Bool)
    case updateDns(value: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
        case timeoutMilliseconds
        case value
    }

    private enum Kind: String, Codable {
        case invoke
        case pollEvents
        case runTime
        case suspend
        case updateDns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .invoke:
            self = .invoke(payload: try container.decode(String.self, forKey: .payload))
        case .pollEvents:
            self = .pollEvents(
                timeoutMilliseconds: try container.decode(Int.self, forKey: .timeoutMilliseconds)
            )
        case .runTime:
            self = .runTime
        case .suspend:
            self = .suspend(value: try container.decode(Bool.self, forKey: .value))
        case .updateDns:
            self = .updateDns(value: try container.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .invoke(payload):
            try container.encode(Kind.invoke, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .pollEvents(timeoutMilliseconds):
            try container.encode(Kind.pollEvents, forKey: .type)
            try container.encode(timeoutMilliseconds, forKey: .timeoutMilliseconds)
        case .runTime:
            try container.encode(Kind.runTime, forKey: .type)
        case let .suspend(value):
            try container.encode(Kind.suspend, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .updateDns(value):
            try container.encode(Kind.updateDns, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct TunnelResponse: Codable {
    var payload: String?
    var events: [String]?
    var runTimeMilliseconds: Int64?
    var error: String?

    static func success(payload: String? = nil) -> TunnelResponse {
        TunnelResponse(payload: payload)
    }

    static func events(_ events: [String]) -> TunnelResponse {
        TunnelResponse(events: events)
    }

    static func runTime(_ milliseconds: Int64?) -> TunnelResponse {
        TunnelResponse(runTimeMilliseconds: milliseconds)
    }

    static func failure(_ message: String) -> TunnelResponse {
        TunnelResponse(error: message)
    }
}

enum TunnelCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
