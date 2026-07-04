import Foundation

/// An intake frame whose payload, envelope, and JavaScript string literals have
/// already been encoded off the MainActor. Delivery owns WebKit transport only.
struct PreEncodedIntakeFrame: Equatable, Sendable {
    let envelopeJSON: String
    let frameJavaScriptLiteral: String
    let pushNonce: String
    let pushNonceJavaScriptLiteral: String
    let encodingRanOnMainThread: Bool

    private init(
        envelopeJSON: String,
        frameJavaScriptLiteral: String,
        pushNonce: String,
        pushNonceJavaScriptLiteral: String,
        encodingRanOnMainThread: Bool
    ) {
        self.envelopeJSON = envelopeJSON
        self.frameJavaScriptLiteral = frameJavaScriptLiteral
        self.pushNonce = pushNonce
        self.pushNonceJavaScriptLiteral = pushNonceJavaScriptLiteral
        self.encodingRanOnMainThread = encodingRanOnMainThread
    }

    @concurrent
    nonisolated static func make<Payload: Encodable & Sendable>(
        metadata: BridgeIntakeFrameMetadata,
        payload: Payload,
        traceContext: BridgeTraceContext?,
        pushNonce: String
    ) async throws -> Self {
        let payloadData = try JSONEncoder().encode(payload)
        return try await makeEncodedPayload(
            metadata: metadata,
            payload: payloadData,
            traceContext: traceContext,
            pushNonce: pushNonce
        )
    }

    @concurrent
    nonisolated static func make<Payload: Encodable & Sendable>(
        payload: Payload,
        metadataFromPayload: @Sendable (Data) throws -> BridgeIntakeFrameMetadata,
        traceContext: BridgeTraceContext?,
        pushNonce: String
    ) async throws -> Self {
        let payloadData = try JSONEncoder().encode(payload)
        return try await makeEncodedPayload(
            metadata: try metadataFromPayload(payloadData),
            payload: payloadData,
            traceContext: traceContext,
            pushNonce: pushNonce
        )
    }

    @concurrent
    nonisolated static func makeEncodedPayload(
        metadata: BridgeIntakeFrameMetadata,
        payload: Data,
        traceContext: BridgeTraceContext?,
        pushNonce: String
    ) async throws -> Self {
        let envelopeJSON = try BridgePushEnvelopeEncoder().encodeIntakeFrame(
            metadata: metadata,
            payload: payload,
            traceContext: traceContext
        )
        return try makeEnvelopeUnchecked(envelopeJSON: envelopeJSON, pushNonce: pushNonce)
    }

    @concurrent
    nonisolated static func makeEnvelope(
        envelopeJSON: String,
        pushNonce: String
    ) async throws -> Self {
        try makeEnvelopeUnchecked(envelopeJSON: envelopeJSON, pushNonce: pushNonce)
    }

    private nonisolated static func makeEnvelopeUnchecked(
        envelopeJSON: String,
        pushNonce: String
    ) throws -> Self {
        try Self(
            envelopeJSON: envelopeJSON,
            frameJavaScriptLiteral: makeJavaScriptStringLiteral(envelopeJSON),
            pushNonce: pushNonce,
            pushNonceJavaScriptLiteral: makeJavaScriptStringLiteral(pushNonce),
            encodingRanOnMainThread: Thread.isMainThread
        )
    }

    private nonisolated static func makeJavaScriptStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let literal = String(data: data, encoding: .utf8) else {
            throw BridgePushEnvelopeEncodingError.invalidEnvelopeUTF8
        }
        return literal
    }
}
