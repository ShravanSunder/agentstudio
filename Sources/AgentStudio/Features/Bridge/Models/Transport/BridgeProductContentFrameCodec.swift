import CryptoKit
import Foundation

enum BridgeProductContentFrameCodec {
    private static let lengthPrefixByteCount = 4
    private static let tagByteCount = 1
    private static let contentSequenceByteCount = 4
    private static let dataOffsetByteCount = 4
    private static let operationCorrelationDigestByteCount = 32
    private static let operationCorrelationEnvelopeByteCount = 33

    static func encode(_ frame: BridgeProductContentFrame) throws -> Data {
        try validatePayload(frame.payload, for: frame.header)
        let body = try encodeTagBody(for: frame)
        let frameByteLength = tagByteCount + contentSequenceByteCount + body.count
        guard frameByteLength <= BridgeProductWireContract.maximumContentFrameBytes else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content frame exceeds its byte ceiling."
            )
        }

        var encodedFrame = Data(capacity: lengthPrefixByteCount + frameByteLength)
        try BridgeProductFrameCodecSupport.appendUInt32BigEndian(frameByteLength, to: &encodedFrame)
        encodedFrame.append(frame.header.frameTag)
        try BridgeProductFrameCodecSupport.appendUInt32BigEndian(
            frame.header.contentSequence,
            to: &encodedFrame
        )
        encodedFrame.append(body)
        return encodedFrame
    }

    static func validatePayload(_ payload: Data, for header: BridgeProductContentHeader) throws {
        try validatePayloadByteLength(payload.count, for: header)
    }

    static func validatePayloadByteLength(
        _ payloadByteLength: Int,
        for header: BridgeProductContentHeader
    ) throws {
        switch header {
        case .data:
            guard
                payloadByteLength > 0,
                payloadByteLength <= BridgeProductWireContract.maximumContentDataPayloadBytes
            else {
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product content data payload is invalid."
                )
            }
        case .accepted, .end, .error, .reset:
            guard payloadByteLength == 0 else {
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product non-data content frame cannot carry a raw payload."
                )
            }
        }
    }

    private static func encodeTagBody(for frame: BridgeProductContentFrame) throws -> Data {
        switch frame.header {
        case .accepted(let header):
            return try encodeControlBody(BridgeProductContentAcceptedControlBody(header: header))
        case .data(let header):
            var body = Data(
                capacity: dataOffsetByteCount + operationCorrelationEnvelopeByteCount + frame.payload.count
            )
            try BridgeProductFrameCodecSupport.appendUInt32BigEndian(header.offsetBytes, to: &body)
            body.append(try operationCorrelationBytes(header.operationCorrelationID))
            body.append(frame.payload)
            return body
        case .end(let header):
            return try encodeControlBody(BridgeProductContentEndControlBody(header: header))
        case .error(let header):
            return try encodeControlBody(BridgeProductContentErrorControlBody(header: header))
        case .reset(let header):
            return try encodeControlBody(BridgeProductContentResetControlBody(header: header))
        }
    }

    private static func encodeControlBody<ControlBody: Encodable>(
        _ body: ControlBody
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bodyData = try encoder.encode(body)
        guard
            !bodyData.isEmpty,
            bodyData.count <= BridgeProductWireContract.maximumContentControlBodyBytes
        else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content control body exceeds its byte ceiling."
            )
        }
        return bodyData
    }

    private static func operationCorrelationBytes(_ value: String?) throws -> Data {
        guard let value else { return Data(repeating: 0, count: operationCorrelationEnvelopeByteCount) }
        try BridgeProductContractDecoding.validateSHA256(value, codingPath: [])
        var bytes = Data(capacity: operationCorrelationEnvelopeByteCount)
        bytes.append(1)
        var index = value.startIndex
        for _ in 0..<operationCorrelationDigestByteCount {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<nextIndex], radix: 16) else {
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product operation correlation is not lowercase SHA-256."
                )
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }
}

extension BridgeProductContentHeader {
    var frameTag: UInt8 {
        switch self {
        case .accepted: 0x01
        case .data: 0x02
        case .end: 0x03
        case .error: 0x04
        case .reset: 0x05
        }
    }
}

final class BridgeProductContentFrameEncoder {
    private let validator: BridgeProductContentStreamValidator
    private let expectedAdmission: BridgeProductContentAdmission
    private var cleanTerminal = false
    private var poisoned = false

    init(expectedRequest: BridgeProductContentRequest) {
        self.expectedAdmission = expectedRequest.admission
        self.validator = BridgeProductContentStreamValidator(expectedRequest: expectedRequest)
    }

    func encode(_ frame: BridgeProductContentFrame) throws -> Data {
        guard !poisoned else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content encoder is unusable after a framing failure."
            )
        }
        do {
            let correlatedFrame = try frame.correlated(to: expectedAdmission)
            let terminalResult = try validator.accept(correlatedFrame)
            let encodedFrame = try BridgeProductContentFrameCodec.encode(correlatedFrame)
            cleanTerminal = terminalResult != nil
            return encodedFrame
        } catch {
            poisoned = true
            throw error
        }
    }

    func finish() throws {
        guard !poisoned else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content encoder is unusable after a framing failure."
            )
        }
        guard cleanTerminal else {
            poisoned = true
            try validator.finish()
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content encoder ended without a terminal frame."
            )
        }
        try validator.finish()
    }
}

extension BridgeProductContentFrame {
    func correlated(to admission: BridgeProductContentAdmission) throws -> Self {
        let correlatedHeader: BridgeProductContentHeader
        switch header {
        case .accepted(let value):
            correlatedHeader = .accepted(
                .init(
                    admission: .init(
                        contentKind: value.identity.contentKind,
                        contentRequestId: value.contentRequestId,
                        declaredByteLength: value.declaredByteLength,
                        expectedSha256: value.expectedSha256,
                        identity: value.identity,
                        leaseId: value.leaseId,
                        operationCorrelationID: admission.operationCorrelationID,
                        maximumBytes: value.maximumBytes,
                        paneSessionId: value.paneSessionId,
                        wireVersion: value.wireVersion,
                        workerDerivationEpoch: value.workerDerivationEpoch,
                        workerInstanceId: value.workerInstanceId
                    )
                )
            )
        case .data(let value):
            correlatedHeader = try .data(
                contentSequence: value.contentSequence,
                offsetBytes: value.offsetBytes,
                operationCorrelationID: admission.operationCorrelationID
            )
        case .end(let value):
            correlatedHeader = try .end(
                contentSequence: value.contentSequence,
                endOfSource: value.endOfSource,
                observedByteLength: value.observedByteLength,
                observedSha256: value.observedSha256,
                operationCorrelationID: admission.operationCorrelationID
            )
        case .error(let value):
            correlatedHeader = try .error(
                contentSequence: value.contentSequence,
                code: value.code,
                retryable: value.retryable,
                safeMessage: value.safeMessage,
                operationCorrelationID: admission.operationCorrelationID
            )
        case .reset(let value):
            correlatedHeader = try .reset(
                contentSequence: value.contentSequence,
                reason: value.reason,
                operationCorrelationID: admission.operationCorrelationID
            )
        }
        return .init(header: correlatedHeader, payload: payload)
    }
}

final class BridgeProductContentStreamValidator {
    private enum LifecycleState {
        case open
        case terminal
        case poisoned
    }

    private let expectedAdmission: BridgeProductContentAdmission
    private var acceptedHeader: BridgeProductContentAcceptedHeader?
    private var contentData = Data()
    private var nextSequence = 0
    private var observedByteLength = 0
    private var lifecycleState = LifecycleState.open

    init(expectedRequest: BridgeProductContentRequest) {
        self.expectedAdmission = expectedRequest.admission
    }

    func accept(_ frame: BridgeProductContentFrame) throws -> BridgeProductContentTerminalResult? {
        switch lifecycleState {
        case .open:
            break
        case .terminal:
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content stream received a post-terminal frame."
            )
        case .poisoned:
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content stream is unusable after a validation failure."
            )
        }
        do {
            return try acceptValidated(frame)
        } catch {
            lifecycleState = .poisoned
            acceptedHeader = nil
            contentData.removeAll()
            throw error
        }
    }

    func finish() throws {
        switch lifecycleState {
        case .terminal:
            return
        case .poisoned:
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content stream is unusable after a validation failure."
            )
        case .open:
            lifecycleState = .poisoned
            acceptedHeader = nil
            contentData.removeAll()
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content response ended without a terminal frame."
            )
        }
    }

    private func acceptValidated(
        _ frame: BridgeProductContentFrame
    ) throws -> BridgeProductContentTerminalResult? {
        try BridgeProductContentFrameCodec.validatePayload(frame.payload, for: frame.header)
        guard frame.header.operationCorrelationID == expectedAdmission.operationCorrelationID else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content operation correlation changed within one stream."
            )
        }

        guard let acceptedHeader else {
            guard case .accepted(let header) = frame.header else {
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product content stream must begin with content.accepted."
                )
            }
            try validateAccepted(header)
            self.acceptedHeader = header
            self.nextSequence = 1
            return nil
        }

        guard frame.header.contentSequence == nextSequence else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content sequence is not contiguous."
            )
        }
        nextSequence += 1

        switch frame.header {
        case .accepted:
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content stream received duplicate content.accepted."
            )
        case .data(let header):
            try acceptData(header: header, payload: frame.payload, acceptedHeader: acceptedHeader)
            return nil
        case .end(let header):
            return try acceptEnd(header: header, acceptedHeader: acceptedHeader)
        case .error(let header):
            lifecycleState = .terminal
            contentData.removeAll()
            return .error(
                .init(
                    code: header.code,
                    contentKind: acceptedHeader.identity.contentKind,
                    descriptorId: acceptedHeader.identity.descriptorId,
                    retryable: header.retryable,
                    safeMessage: header.safeMessage
                )
            )
        case .reset(let header):
            lifecycleState = .terminal
            contentData.removeAll()
            return .reset(
                .init(
                    contentKind: acceptedHeader.identity.contentKind,
                    descriptorId: acceptedHeader.identity.descriptorId,
                    reason: header.reason,
                    retryable: true
                )
            )
        }
    }

    private func validateAccepted(_ header: BridgeProductContentAcceptedHeader) throws {
        guard
            header.contentRequestId == expectedAdmission.contentRequestId,
            header.leaseId == expectedAdmission.leaseId,
            header.paneSessionId == expectedAdmission.paneSessionId,
            header.workerDerivationEpoch == expectedAdmission.workerDerivationEpoch,
            header.workerInstanceId == expectedAdmission.workerInstanceId,
            header.maximumBytes == expectedAdmission.maximumBytes,
            header.declaredByteLength == expectedAdmission.declaredByteLength,
            header.expectedSha256 == expectedAdmission.expectedSha256,
            header.identity == expectedAdmission.identity
        else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content acceptance does not match its issued request."
            )
        }
    }

    private func acceptData(
        header: BridgeProductContentDataHeader,
        payload: Data,
        acceptedHeader: BridgeProductContentAcceptedHeader
    ) throws {
        guard header.offsetBytes == observedByteLength else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content data offset is not contiguous."
            )
        }
        let (nextObservedByteLength, overflowed) = observedByteLength.addingReportingOverflow(payload.count)
        guard !overflowed, nextObservedByteLength <= acceptedHeader.maximumBytes else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content bytes exceed their maximum."
            )
        }
        if let declaredByteLength = acceptedHeader.declaredByteLength {
            guard nextObservedByteLength <= declaredByteLength else {
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product content bytes exceed their declared length."
                )
            }
        }
        contentData.append(payload)
        observedByteLength = nextObservedByteLength
    }

    private func acceptEnd(
        header: BridgeProductContentEndHeader,
        acceptedHeader: BridgeProductContentAcceptedHeader
    ) throws -> BridgeProductContentTerminalResult {
        if acceptedHeader.identity.contentKind == .fileContent, !header.endOfSource {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product File content terminal must reach the end of source."
            )
        }
        guard header.observedByteLength == observedByteLength else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content end length does not match received bytes."
            )
        }
        if let declaredByteLength = acceptedHeader.declaredByteLength {
            guard header.observedByteLength == declaredByteLength else {
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product content end length does not match its declaration."
                )
            }
        }
        let observedSha256 = SHA256.hash(data: contentData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard observedSha256 == header.observedSha256 else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content end digest does not match received bytes."
            )
        }
        if let expectedSha256 = acceptedHeader.expectedSha256 {
            guard observedSha256 == expectedSha256 else {
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product content digest conflicts with its authoritative expectation."
                )
            }
        }
        let completedData = contentData
        lifecycleState = .terminal
        contentData.removeAll()
        return .complete(
            .init(
                bytes: completedData,
                contentKind: acceptedHeader.identity.contentKind,
                descriptorId: acceptedHeader.identity.descriptorId,
                endOfSource: header.endOfSource,
                observedSha256: observedSha256
            )
        )
    }
}
