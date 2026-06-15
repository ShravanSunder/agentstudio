import Foundation

struct BridgeTraceContextFactory: Sendable {
    private let makeTraceIdValue: @Sendable () -> String
    private let makeSpanIdValue: @Sendable () -> String

    init(
        makeTraceId: @escaping @Sendable () -> String,
        makeSpanId: @escaping @Sendable () -> String
    ) {
        self.makeTraceIdValue = makeTraceId
        self.makeSpanIdValue = makeSpanId
    }

    func makeRootContext() -> BridgeTraceContext? {
        try? BridgeTraceContext(
            traceId: makeTraceIdValue(),
            spanId: makeSpanIdValue(),
            parentSpanId: nil,
            sampled: true
        )
    }

    func makeChildContext(parent: BridgeTraceContext?) -> BridgeTraceContext? {
        guard let parent else {
            return makeRootContext()
        }
        return try? BridgeTraceContext(
            traceId: parent.traceId,
            spanId: makeSpanIdValue(),
            parentSpanId: parent.spanId,
            sampled: parent.sampled
        )
    }

    static let live = Self(
        makeTraceId: { randomLowercaseHex(byteCount: 16) },
        makeSpanId: { randomLowercaseHex(byteCount: 8) }
    )

    private static func randomLowercaseHex(byteCount: Int) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        for _ in 0..<byteCount {
            bytes.append(UInt8.random(in: 0...UInt8.max))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
