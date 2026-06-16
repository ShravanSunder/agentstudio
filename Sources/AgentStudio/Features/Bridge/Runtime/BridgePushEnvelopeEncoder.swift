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
        guard String(data: payload, encoding: .utf8) != nil else {
            throw BridgePushEnvelopeEncodingError.invalidPayloadUTF8
        }

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

    private func append(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private func appendJSONString(_ string: String, to data: inout Data) throws {
        let encodedString = try JSONEncoder().encode(string)
        data.append(encodedString)
    }
}

enum BridgePushEnvelopeEncodingError: Error, LocalizedError, Sendable {
    case invalidEnvelopeUTF8
    case invalidPayloadUTF8

    var errorDescription: String? {
        switch self {
        case .invalidEnvelopeUTF8:
            "Unable to encode push envelope as UTF-8"
        case .invalidPayloadUTF8:
            "Push payload must be UTF-8 JSON"
        }
    }
}
