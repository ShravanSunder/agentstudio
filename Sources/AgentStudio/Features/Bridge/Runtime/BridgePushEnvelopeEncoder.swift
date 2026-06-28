import Foundation

struct BridgePushEnvelopeEncoder: Sendable {
    func encode(
        metadata: BridgePushEnvelopeMetadata,
        payload: Data,
        pushId: UUID,
        traceContext: BridgeTraceContext?
    ) throws -> String {
        let envelopeData = try encodeData(
            metadata: metadata,
            payload: payload,
            pushId: pushId,
            traceContext: traceContext
        )
        guard let envelopeString = String(data: envelopeData, encoding: .utf8) else {
            throw BridgePushEnvelopeEncodingError.invalidEnvelopeUTF8
        }
        return envelopeString
    }

    func encodeData(
        metadata: BridgePushEnvelopeMetadata,
        payload: Data,
        pushId: UUID,
        traceContext: BridgeTraceContext?
    ) throws -> Data {
        let traceContextData = try traceContext.map { try JSONEncoder().encode($0) }
        var envelope = Data()
        envelope.reserveCapacity(payload.count + 256 + (traceContextData?.count ?? 0))

        append("{", to: &envelope)
        append(#""__v":1"#, to: &envelope)
        append(#","__revision":"#, to: &envelope)
        append(String(metadata.revision), to: &envelope)
        append(#","__epoch":"#, to: &envelope)
        append(String(metadata.epoch), to: &envelope)
        append(#","__pushId":"#, to: &envelope)
        try appendJSONString(pushId.uuidString, to: &envelope)
        append(#","store":"#, to: &envelope)
        try appendJSONString(metadata.store.rawValue, to: &envelope)
        append(#","op":"#, to: &envelope)
        try appendJSONString(metadata.op.rawValue, to: &envelope)
        append(#","level":"#, to: &envelope)
        try appendJSONString(metadata.level.rawValue, to: &envelope)
        append(#","slice":"#, to: &envelope)
        try appendJSONString(metadata.slice.rawValue, to: &envelope)
        append(#","payload":"#, to: &envelope)
        envelope.append(payload)
        if let traceContextData {
            append(#","__traceContext":"#, to: &envelope)
            envelope.append(traceContextData)
        }
        append("}", to: &envelope)
        return envelope
    }

    func encodeIntakeFrame(
        metadata: BridgeIntakeFrameMetadata,
        payload: Data,
        traceContext: BridgeTraceContext?
    ) throws -> String {
        let traceContextData = try traceContext.map { try JSONEncoder().encode($0) }
        var frame = Data()
        frame.reserveCapacity(payload.count + 192 + (traceContextData?.count ?? 0))

        append("{", to: &frame)
        append(#""kind":"#, to: &frame)
        try appendJSONString(metadata.kind.rawValue, to: &frame)
        append(#","streamId":"#, to: &frame)
        try appendJSONString(metadata.streamId, to: &frame)
        append(#","generation":"#, to: &frame)
        append(String(metadata.generation), to: &frame)
        append(#","sequence":"#, to: &frame)
        append(String(metadata.sequence), to: &frame)
        switch metadata.kind {
        case .snapshot, .delta, .invalidate, .reset:
            append(#","payload":"#, to: &frame)
            frame.append(payload)
        case .close:
            break
        case .error:
            guard let message = metadata.message, !message.isEmpty else {
                throw BridgePushEnvelopeEncodingError.missingIntakeFrameMessage
            }
            append(#","message":"#, to: &frame)
            try appendJSONString(message, to: &frame)
        }
        if let traceContextData {
            append(#","__traceContext":"#, to: &frame)
            frame.append(traceContextData)
        }
        append("}", to: &frame)

        guard let frameString = String(data: frame, encoding: .utf8) else {
            throw BridgePushEnvelopeEncodingError.invalidEnvelopeUTF8
        }
        return frameString
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private func appendJSONString(_ string: String, to data: inout Data) throws {
        let encodedString = try JSONEncoder().encode(string)
        data.append(encodedString)
    }
}

enum BridgeIntakeFrameKind: String, Sendable {
    case snapshot
    case delta
    case invalidate
    case reset
    case close
    case error
}

struct BridgeIntakeFrameMetadata: Sendable {
    let kind: BridgeIntakeFrameKind
    let streamId: String
    let generation: Int
    let sequence: Int
    let message: String?

    init(
        kind: BridgeIntakeFrameKind,
        streamId: String,
        generation: Int,
        sequence: Int,
        message: String? = nil
    ) {
        self.kind = kind
        self.streamId = streamId
        self.generation = generation
        self.sequence = sequence
        self.message = message
    }
}

enum BridgePushEnvelopeEncodingError: Error, LocalizedError, Sendable {
    case invalidEnvelopeUTF8
    case missingIntakeFrameMessage

    var errorDescription: String? {
        switch self {
        case .invalidEnvelopeUTF8:
            "Unable to encode push envelope as UTF-8"
        case .missingIntakeFrameMessage:
            "Unable to encode error intake frame without a non-empty message"
        }
    }
}
