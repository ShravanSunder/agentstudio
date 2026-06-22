import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge push envelope encoder")
struct BridgePushEnvelopeEncoderTests {
    @Test("encodes metadata and preserves raw JSON payload")
    func encodesMetadataAndPreservesRawJSONPayload() throws {
        let metadata = BridgePushEnvelopeMetadata(
            store: .diff,
            op: .replace,
            level: .cold,
            slice: .diffPackageMetadata,
            revision: 7,
            epoch: 3
        )
        let payload = Data(#"{"package":{"orderedItemIds":["item-1"]}}"#.utf8)
        let pushId = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let envelope = try BridgePushEnvelopeEncoder().encode(
            metadata: metadata,
            payload: payload,
            pushId: pushId,
            traceContext: nil
        )

        #expect(envelope.contains(#""payload":{"package":{"orderedItemIds":["item-1"]}}"#))
        #expect(!envelope.contains(#""payload":"{\"package\""#))

        let envelopeData = try #require(envelope.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: envelopeData) as? [String: Any])
        #expect(object["__v"] as? Int == 1)
        #expect(object["__revision"] as? Int == 7)
        #expect(object["__epoch"] as? Int == 3)
        #expect(object["__pushId"] as? String == pushId.uuidString)
        #expect(object["store"] as? String == "diff")
        #expect(object["op"] as? String == "replace")
        #expect(object["level"] as? String == "cold")
        #expect(object["slice"] as? String == "diff_package_metadata")

        let decodedPayload = try #require(object["payload"] as? [String: Any])
        let decodedPackage = try #require(decodedPayload["package"] as? [String: Any])
        #expect(decodedPackage["orderedItemIds"] as? [String] == ["item-1"])
    }

    @Test("encodes optional trace context outside payload")
    func encodesOptionalTraceContextOutsidePayload() throws {
        let traceContext = try BridgeTraceContext(
            traceId: "11111111111111111111111111111111",
            spanId: "2222222222222222",
            parentSpanId: "3333333333333333",
            sampled: true
        )
        let envelope = try BridgePushEnvelopeEncoder().encode(
            metadata: BridgePushEnvelopeMetadata(
                store: .diff,
                op: .merge,
                level: .hot,
                slice: .diffStatus,
                revision: 1,
                epoch: 2
            ),
            payload: Data(#"{"status":"ready"}"#.utf8),
            pushId: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            traceContext: traceContext
        )

        let envelopeData = try #require(envelope.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: envelopeData) as? [String: Any])
        let decodedTraceContext = try #require(object["__traceContext"] as? [String: Any])
        let decodedPayload = try #require(object["payload"] as? [String: Any])

        #expect(decodedPayload["status"] as? String == "ready")
        #expect(decodedTraceContext["traceId"] as? String == traceContext.traceId)
        #expect(decodedTraceContext["spanId"] as? String == traceContext.spanId)
        #expect(decodedTraceContext["parentSpanId"] as? String == traceContext.parentSpanId)
        #expect(decodedTraceContext["sampled"] as? Bool == true)
    }

    @Test("rejects non UTF-8 payloads before transport")
    func rejectsNonUTF8PayloadsBeforeTransport() {
        #expect(throws: BridgePushEnvelopeEncodingError.self) {
            _ = try BridgePushEnvelopeEncoder().encode(
                metadata: BridgePushEnvelopeMetadata(
                    store: .diff,
                    op: .merge,
                    level: .hot,
                    slice: .diffStatus,
                    revision: 1,
                    epoch: 1
                ),
                payload: Data([0xFF]),
                pushId: UUID(),
                traceContext: nil
            )
        }
    }
}
