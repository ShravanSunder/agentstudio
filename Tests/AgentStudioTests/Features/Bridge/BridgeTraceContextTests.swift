import Testing

@testable import AgentStudio

@Suite
struct BridgeTraceContextTests {
    @Test
    func traceContextSerializesSampledW3CTraceparent() throws {
        let context = try BridgeTraceContext(
            traceId: "11111111111111111111111111111111",
            spanId: "2222222222222222",
            parentSpanId: "3333333333333333",
            sampled: true
        )

        #expect(context.traceparent == "00-11111111111111111111111111111111-2222222222222222-01")
    }

    @Test
    func traceContextParsesContentFetchTraceparentHeader() throws {
        let context = try BridgeTraceContext.parseTraceparent(
            "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00"
        )

        #expect(context.traceId == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(context.spanId == "bbbbbbbbbbbbbbbb")
        #expect(context.parentSpanId == nil)
        #expect(!context.sampled)
    }

    @Test
    func traceContextRejectsInvalidAndAllZeroIdentifiers() {
        #expect(throws: BridgeTraceContext.ValidationError.self) {
            _ = try BridgeTraceContext(
                traceId: "00000000000000000000000000000000",
                spanId: "2222222222222222",
                parentSpanId: nil,
                sampled: true
            )
        }
        #expect(throws: BridgeTraceContext.ValidationError.self) {
            _ = try BridgeTraceContext.parseTraceparent(
                "00-11111111111111111111111111111111-not-a-span-01"
            )
        }
    }
}
