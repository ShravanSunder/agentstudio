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

    @Test("encodes intake frame identity outside payload without authority fields")
    func encodesIntakeFrameIdentityOutsidePayloadWithoutAuthorityFields() throws {
        let traceContext = try BridgeTraceContext(
            traceId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            spanId: "bbbbbbbbbbbbbbbb",
            parentSpanId: nil,
            sampled: true
        )

        let frame = try BridgePushEnvelopeEncoder().encodeIntakeFrame(
            metadata: BridgeIntakeFrameMetadata(
                kind: .snapshot,
                streamId: "stream-1",
                generation: 4,
                sequence: 9
            ),
            payload: Data(
                #"{"resourceUrl":"agentstudio://resource/content/leak","path":"/private/tmp/leak.swift"}"#.utf8),
            traceContext: traceContext
        )

        let frameData = try #require(frame.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: frameData) as? [String: Any])

        #expect(object["kind"] as? String == "snapshot")
        #expect(object["streamId"] as? String == "stream-1")
        #expect(object["generation"] as? Int == 4)
        #expect(object["sequence"] as? Int == 9)
        #expect(object["path"] == nil)
        #expect(object["resourceUrl"] == nil)
        #expect(object["capabilityHandle"] == nil)

        let decodedTraceContext = try #require(object["__traceContext"] as? [String: Any])
        let decodedPayload = try #require(object["payload"] as? [String: Any])
        #expect(decodedTraceContext["traceId"] as? String == traceContext.traceId)
        #expect(decodedPayload["resourceUrl"] as? String == "agentstudio://resource/content/leak")
        #expect(decodedPayload["path"] as? String == "/private/tmp/leak.swift")
    }

    @Test("encodes intake lifecycle frames with schema-compatible shapes")
    func encodesIntakeLifecycleFramesWithSchemaCompatibleShapes() throws {
        let encoder = BridgePushEnvelopeEncoder()

        let errorFrame = try encoder.encodeIntakeFrame(
            metadata: BridgeIntakeFrameMetadata(
                kind: .error,
                streamId: "stream-1",
                generation: 4,
                sequence: 10,
                message: "backend stream failed"
            ),
            payload: Data(#"{"ignored":true}"#.utf8),
            traceContext: nil
        )
        let closeFrame = try encoder.encodeIntakeFrame(
            metadata: BridgeIntakeFrameMetadata(
                kind: .close,
                streamId: "stream-1",
                generation: 4,
                sequence: 11
            ),
            payload: Data(#"{"ignored":true}"#.utf8),
            traceContext: nil
        )
        let resetFrame = try encoder.encodeIntakeFrame(
            metadata: BridgeIntakeFrameMetadata(
                kind: .reset,
                streamId: "stream-1",
                generation: 5,
                sequence: 0
            ),
            payload: Data(#"{"ignored":true}"#.utf8),
            traceContext: nil
        )

        let errorObject = try decodeJSONObject(errorFrame)
        let closeObject = try decodeJSONObject(closeFrame)
        let resetObject = try decodeJSONObject(resetFrame)

        #expect(errorObject["kind"] as? String == "error")
        #expect(errorObject["message"] as? String == "backend stream failed")
        #expect(errorObject["payload"] == nil)
        #expect(closeObject["kind"] as? String == "close")
        #expect(closeObject["payload"] == nil)
        #expect(resetObject["kind"] as? String == "reset")
        #expect(resetObject["payload"] == nil)
    }

    @Test("rejects error intake frames without a message")
    func rejectsErrorIntakeFramesWithoutMessage() {
        #expect(throws: BridgePushEnvelopeEncodingError.self) {
            _ = try BridgePushEnvelopeEncoder().encodeIntakeFrame(
                metadata: BridgeIntakeFrameMetadata(
                    kind: .error,
                    streamId: "stream-1",
                    generation: 4,
                    sequence: 10
                ),
                payload: Data(#"{}"#.utf8),
                traceContext: nil
            )
        }
    }

    private func decodeJSONObject(_ json: String) throws -> [String: Any] {
        let data = try #require(json.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
