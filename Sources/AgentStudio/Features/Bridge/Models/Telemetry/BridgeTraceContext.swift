import Foundation

struct BridgeTraceContext: Codable, Equatable, Sendable {
    enum ValidationError: Error, Equatable {
        case invalidParentSpanId
        case invalidSpanId
        case invalidTraceId
        case invalidTraceparent
    }

    let traceId: String
    let spanId: String
    let parentSpanId: String?
    let sampled: Bool

    init(
        traceId: String,
        spanId: String,
        parentSpanId: String?,
        sampled: Bool
    ) throws {
        guard Self.isValidTraceId(traceId) else {
            throw ValidationError.invalidTraceId
        }
        guard Self.isValidSpanId(spanId) else {
            throw ValidationError.invalidSpanId
        }
        if let parentSpanId, !Self.isValidSpanId(parentSpanId) {
            throw ValidationError.invalidParentSpanId
        }

        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.sampled = sampled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            traceId: try container.decode(String.self, forKey: .traceId),
            spanId: try container.decode(String.self, forKey: .spanId),
            parentSpanId: try container.decodeIfPresent(String.self, forKey: .parentSpanId),
            sampled: try container.decode(Bool.self, forKey: .sampled)
        )
    }

    var traceparent: String {
        "00-\(traceId)-\(spanId)-\(sampled ? "01" : "00")"
    }

    static func parseTraceparent(_ value: String) throws -> Self {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "00", isValidTraceFlags(parts[3]) else {
            throw ValidationError.invalidTraceparent
        }
        return try Self(
            traceId: parts[1],
            spanId: parts[2],
            parentSpanId: nil,
            sampled: traceFlagsAreSampled(parts[3])
        )
    }

    private static func isValidTraceId(_ value: String) -> Bool {
        isValidLowercaseHex(value, requiredLength: 32)
    }

    private static func isValidSpanId(_ value: String) -> Bool {
        isValidLowercaseHex(value, requiredLength: 16)
    }

    private static func isValidTraceFlags(_ value: String) -> Bool {
        isValidLowercaseHex(value, requiredLength: 2, allowAllZero: true)
    }

    private static func traceFlagsAreSampled(_ value: String) -> Bool {
        guard let flags = UInt8(value, radix: 16) else {
            return false
        }
        return flags & 1 == 1
    }

    private static func isValidLowercaseHex(
        _ value: String,
        requiredLength: Int,
        allowAllZero: Bool = false
    ) -> Bool {
        guard value.count == requiredLength else {
            return false
        }
        guard allowAllZero || value.utf8.contains(where: { $0 != 48 }) else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            byte >= 48 && byte <= 57 || byte >= 97 && byte <= 102
        }
    }
}
