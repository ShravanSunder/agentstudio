import Foundation

final class BridgeProductContentFrameDecoder {
    private static let lengthPrefixByteCount = 4
    private static let commonFramePrefixByteCount = 9
    private static let minimumFrameBodyByteCount = 5
    private static let dataOffsetByteCount = 4

    private let maximumFrameBytes: Int
    private var accounting = BridgeProductFrameDecoderIngressAccounting()
    private let storageAccounting = BridgeProductFrameDecoderStorageAccounting()
    private var decodingState: DecodingState = .prefix(frameByteLength: nil, accumulator: nil)
    private var acceptedHeader: BridgeProductContentAcceptedHeader?
    private var nextContentSequence = 0
    private var observedByteLength = 0
    private var terminal = false
    private var finished = false
    private var poisoned = false

    var diagnostics: BridgeProductFrameDecoderDiagnostics {
        accounting.diagnostics
    }

    var storageDiagnostics: BridgeProductFrameDecoderStorageDiagnostics {
        storageAccounting.diagnostics
    }

    init(maximumFrameBytes: Int = BridgeProductWireContract.maximumContentFrameBytes) throws {
        guard maximumFrameBytes > 0,
            maximumFrameBytes <= BridgeProductWireContract.maximumContentFrameBytes
        else {
            throw BridgeProductFrameCodecError.invalidConfiguration
        }
        self.maximumFrameBytes = maximumFrameBytes
    }

    func append(_ chunk: Data) throws -> [BridgeProductContentFrame] {
        guard !poisoned else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content decoder is unusable after a framing failure."
            )
        }
        guard !finished else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content decoder cannot accept bytes after finish."
            )
        }
        if terminal, !chunk.isEmpty {
            accounting.recordReceivedBytes(chunk.count)
            poison(
                failureCode: .framePayloadInvalid,
                discardedTailByteCount: chunk.count
            )
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content decoder cannot accept post-terminal bytes."
            )
        }
        let consumedByteCountBeforeAppend = diagnostics.consumedByteCount
        accounting.recordReceivedBytes(chunk.count)
        do {
            let decodedFrames = try appendValidated(chunk)
            accounting.commitEmittedFrames(decodedFrames.count)
            return decodedFrames
        } catch let failure as ClassifiedFailure {
            let consumedByteCount = diagnostics.consumedByteCount - consumedByteCountBeforeAppend
            poison(
                failureCode: failure.code,
                discardedTailByteCount: chunk.count - consumedByteCount
            )
            throw failure.underlyingError
        } catch {
            let consumedByteCount = diagnostics.consumedByteCount - consumedByteCountBeforeAppend
            poison(
                failureCode: .frameDecodeInvalid,
                discardedTailByteCount: chunk.count - consumedByteCount
            )
            throw error
        }
    }

    func finish() throws {
        guard !poisoned else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product content decoder is unusable after a framing failure."
            )
        }
        guard !finished else { return }
        guard decodingState.isAtFrameBoundary, terminal else {
            poison(
                failureCode: .truncatedFrame,
                discardedTailByteCount: diagnostics.retainedByteCount
            )
            throw BridgeProductFrameCodecError.truncatedFrame
        }
        finished = true
        accounting.finish()
    }

    private func appendValidated(_ chunk: Data) throws -> [BridgeProductContentFrame] {
        guard !chunk.isEmpty else { return [] }
        var decodedFrames: [BridgeProductContentFrame] = []
        var sourceOffset = 0

        while sourceOffset < chunk.count {
            switch decodingState {
            case .prefix(let frameByteLength, let accumulator):
                try consumePrefix(
                    frameByteLength: frameByteLength,
                    accumulator: accumulator,
                    from: chunk,
                    sourceOffset: &sourceOffset
                )

            case .controlBody(let frameTag, let contentSequence, let prefix, let body):
                if let frame = try consumeControlBody(
                    frameTag: frameTag,
                    contentSequence: contentSequence,
                    prefix: prefix,
                    body: body,
                    from: chunk,
                    sourceOffset: &sourceOffset
                ) {
                    decodedFrames.append(frame)
                }

            case .dataOffset(let contentSequence, let payloadByteLength, let prefix, let offset):
                try consumeDataOffset(
                    contentSequence: contentSequence,
                    payloadByteLength: payloadByteLength,
                    prefix: prefix,
                    offset: offset,
                    from: chunk,
                    sourceOffset: &sourceOffset
                )

            case .dataPayload(let state):
                if let frame = try consumeDataPayload(
                    state,
                    from: chunk,
                    sourceOffset: &sourceOffset
                ) {
                    decodedFrames.append(frame)
                }
            }
        }
        return decodedFrames
    }

    private func consumePrefix(
        frameByteLength: Int?,
        accumulator existingAccumulator: BridgeProductFrameByteAccumulator?,
        from chunk: Data,
        sourceOffset: inout Int
    ) throws {
        let accumulator =
            existingAccumulator
            ?? BridgeProductFrameByteAccumulator(
                capacity: Self.commonFramePrefixByteCount,
                storageAccounting: storageAccounting
            )
        let targetByteCount =
            frameByteLength == nil
            ? Self.lengthPrefixByteCount
            : Self.commonFramePrefixByteCount
        let copiedByteCount = accumulator.append(
            from: chunk,
            sourceOffset: &sourceOffset,
            until: targetByteCount
        )
        accounting.recordConsumedCopy(
            copiedByteCount,
            retainedByteCount: accumulator.count,
            state: frameByteLength == nil ? .awaitingLengthPrefix : .awaitingContentPrefix
        )
        guard accumulator.count == targetByteCount else {
            decodingState = .prefix(
                frameByteLength: frameByteLength,
                accumulator: accumulator
            )
            return
        }

        guard let frameByteLength else {
            try admitFrameLength(from: accumulator)
            return
        }
        try admitCommonPrefix(frameByteLength: frameByteLength, prefix: accumulator)
    }

    private func admitFrameLength(from prefix: BridgeProductFrameByteAccumulator) throws {
        let frameByteLength = prefix.readUInt32BigEndian(at: 0)
        guard frameByteLength >= Self.minimumFrameBodyByteCount else {
            throw failure(
                .frameLengthInvalid,
                "Bridge product content frame length is invalid."
            )
        }
        guard frameByteLength <= maximumFrameBytes else {
            throw failure(
                .frameLengthExceedsCeiling,
                "Bridge product content frame exceeds its byte ceiling."
            )
        }
        decodingState = .prefix(frameByteLength: frameByteLength, accumulator: prefix)
        accounting.transition(to: .awaitingContentPrefix, retainedByteCount: prefix.count)
    }

    private func admitCommonPrefix(
        frameByteLength: Int,
        prefix: BridgeProductFrameByteAccumulator
    ) throws {
        let frameTag = prefix.byte(at: Self.lengthPrefixByteCount)
        guard (0x01...0x05).contains(frameTag) else {
            throw failure(
                .contentFrameTagInvalid,
                "Bridge product response used an unknown content frame tag."
            )
        }
        let contentSequence = prefix.readUInt32BigEndian(at: Self.lengthPrefixByteCount + 1)
        try validateLifecycleAdmission(frameTag: frameTag, contentSequence: contentSequence)
        let tagBodyByteLength = frameByteLength - Self.minimumFrameBodyByteCount

        if frameTag == 0x02 {
            try admitDataOffset(
                contentSequence: contentSequence,
                tagBodyByteLength: tagBodyByteLength,
                prefix: prefix
            )
            return
        }

        guard tagBodyByteLength > 0 else {
            throw failure(
                .contentControlBodyLengthInvalid,
                "Bridge product content control body length is invalid."
            )
        }
        guard tagBodyByteLength <= BridgeProductWireContract.maximumContentControlBodyBytes else {
            throw failure(
                .contentControlBodyExceedsCeiling,
                "Bridge product content control body exceeds its byte ceiling."
            )
        }
        let body = BridgeProductFrameByteAccumulator(
            capacity: tagBodyByteLength,
            storageAccounting: storageAccounting
        )
        decodingState = .controlBody(
            frameTag: frameTag,
            contentSequence: contentSequence,
            prefix: prefix,
            body: body
        )
        accounting.transition(
            to: .awaitingContentControlBody,
            retainedByteCount: prefix.count
        )
    }

    private func admitDataOffset(
        contentSequence: Int,
        tagBodyByteLength: Int,
        prefix: BridgeProductFrameByteAccumulator
    ) throws {
        let payloadByteLength = tagBodyByteLength - Self.dataOffsetByteCount
        guard
            payloadByteLength > 0,
            payloadByteLength <= BridgeProductWireContract.maximumContentDataPayloadBytes
        else {
            throw failure(
                .framePayloadInvalid,
                "Bridge product content data payload length is invalid."
            )
        }
        let offset = BridgeProductFrameByteAccumulator(
            capacity: Self.dataOffsetByteCount,
            storageAccounting: storageAccounting
        )
        decodingState = .dataOffset(
            contentSequence: contentSequence,
            payloadByteLength: payloadByteLength,
            prefix: prefix,
            offset: offset
        )
        accounting.transition(to: .awaitingFrameBody, retainedByteCount: prefix.count)
    }

    private func consumeControlBody(
        frameTag: UInt8,
        contentSequence: Int,
        prefix: BridgeProductFrameByteAccumulator,
        body: BridgeProductFrameByteAccumulator,
        from chunk: Data,
        sourceOffset: inout Int
    ) throws -> BridgeProductContentFrame? {
        let copiedByteCount = body.append(from: chunk, sourceOffset: &sourceOffset)
        accounting.recordConsumedCopy(
            copiedByteCount,
            retainedByteCount: prefix.count + body.count,
            state: .awaitingContentControlBody
        )
        guard body.count == body.capacity else { return nil }

        let frame = try decodeControlFrame(
            frameTag: frameTag,
            contentSequence: contentSequence,
            body: body.takeData()
        )
        if terminal, sourceOffset < chunk.count {
            throw failure(
                .framePayloadInvalid,
                "Bridge product content terminal frame has trailing bytes."
            )
        }
        resetToFrameBoundary()
        return frame
    }

    private func consumeDataOffset(
        contentSequence: Int,
        payloadByteLength: Int,
        prefix: BridgeProductFrameByteAccumulator,
        offset: BridgeProductFrameByteAccumulator,
        from chunk: Data,
        sourceOffset: inout Int
    ) throws {
        let copiedByteCount = offset.append(from: chunk, sourceOffset: &sourceOffset)
        accounting.recordConsumedCopy(
            copiedByteCount,
            retainedByteCount: prefix.count + offset.count,
            state: .awaitingFrameBody
        )
        guard offset.count == offset.capacity else { return }

        let offsetBytes = offset.readUInt32BigEndian(at: 0)
        guard offsetBytes <= BridgeProductWireContract.maximumContentStreamBytes else {
            throw failure(
                .framePayloadInvalid,
                "Bridge product content data offset exceeds its product maximum."
            )
        }
        guard let acceptedHeader,
            offsetBytes == observedByteLength,
            offsetBytes <= acceptedHeader.maximumBytes,
            payloadByteLength <= acceptedHeader.maximumBytes - offsetBytes,
            acceptedHeader.declaredByteLength.map({
                offsetBytes <= $0 && payloadByteLength <= $0 - offsetBytes
            }) ?? true
        else {
            throw failure(
                .framePayloadInvalid,
                "Bridge product content data offset or length is not contiguous."
            )
        }
        let payload = BridgeProductFrameByteAccumulator(
            capacity: payloadByteLength,
            storageAccounting: storageAccounting
        )
        decodingState = .dataPayload(
            .init(
                contentSequence: contentSequence,
                offsetBytes: offsetBytes,
                prefix: prefix,
                offset: offset,
                payload: payload
            )
        )
    }

    private func consumeDataPayload(
        _ state: DataPayloadState,
        from chunk: Data,
        sourceOffset: inout Int
    ) throws -> BridgeProductContentFrame? {
        let copiedByteCount = state.payload.append(from: chunk, sourceOffset: &sourceOffset)
        accounting.recordConsumedCopy(
            copiedByteCount,
            retainedByteCount: state.prefix.count + state.offset.count + state.payload.count,
            state: .awaitingFrameBody
        )
        guard state.payload.count == state.payload.capacity else { return nil }
        guard acceptedHeader != nil else {
            throw failure(
                .framePayloadInvalid,
                "Bridge product content data arrived before acceptance."
            )
        }

        let payload = state.payload.takeData()
        let header = try BridgeProductContentDataHeader(
            contentSequence: state.contentSequence,
            offsetBytes: state.offsetBytes
        )
        observedByteLength += payload.count
        nextContentSequence += 1
        resetToFrameBoundary()
        return .init(header: .data(header), payload: payload)
    }

    private func decodeControlFrame(
        frameTag: UInt8,
        contentSequence: Int,
        body: Data
    ) throws -> BridgeProductContentFrame {
        do {
            switch frameTag {
            case 0x01:
                let wireBody = try BridgeProductFrameCodecSupport.decodeStrictJSON(
                    BridgeProductContentAcceptedControlBody.self,
                    from: body
                )
                let header = BridgeProductContentAcceptedHeader(wireBody: wireBody)
                acceptedHeader = header
                nextContentSequence = 1
                observedByteLength = 0
                return .init(header: .accepted(header), payload: Data())

            case 0x03:
                guard let acceptedHeader else {
                    throw BridgeProductFrameCodecError.invalidFrame(
                        "Bridge product content end arrived before acceptance."
                    )
                }
                let wireBody = try BridgeProductFrameCodecSupport.decodeStrictJSON(
                    BridgeProductContentEndControlBody.self,
                    from: body
                )
                guard wireBody.observedByteLength == observedByteLength,
                    acceptedHeader.declaredByteLength.map({ $0 == observedByteLength }) ?? true
                else {
                    throw BridgeProductFrameCodecError.invalidFrame(
                        "Bridge product content end length does not match received bytes."
                    )
                }
                let header = BridgeProductContentEndHeader(
                    contentSequence: contentSequence,
                    wireBody: wireBody
                )
                markTerminal()
                return .init(header: .end(header), payload: Data())

            case 0x04:
                guard acceptedHeader != nil else {
                    throw BridgeProductFrameCodecError.invalidFrame(
                        "Bridge product content error arrived before acceptance."
                    )
                }
                let wireBody = try BridgeProductFrameCodecSupport.decodeStrictJSON(
                    BridgeProductContentErrorControlBody.self,
                    from: body
                )
                let header = BridgeProductContentErrorHeader(
                    contentSequence: contentSequence,
                    wireBody: wireBody
                )
                markTerminal()
                return .init(header: .error(header), payload: Data())

            case 0x05:
                guard acceptedHeader != nil else {
                    throw BridgeProductFrameCodecError.invalidFrame(
                        "Bridge product content reset arrived before acceptance."
                    )
                }
                let wireBody = try BridgeProductFrameCodecSupport.decodeStrictJSON(
                    BridgeProductContentResetControlBody.self,
                    from: body
                )
                let header = BridgeProductContentResetHeader(
                    contentSequence: contentSequence,
                    wireBody: wireBody
                )
                markTerminal()
                return .init(header: .reset(header), payload: Data())

            default:
                throw BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product data frame reached the control decoder."
                )
            }
        } catch {
            throw ClassifiedFailure(code: .frameDecodeInvalid, underlyingError: error)
        }
    }

    private func validateLifecycleAdmission(
        frameTag: UInt8,
        contentSequence: Int
    ) throws {
        guard !terminal else {
            throw failure(
                .framePayloadInvalid,
                "Bridge product content stream received a post-terminal frame."
            )
        }
        if frameTag == 0x01 {
            guard acceptedHeader == nil, contentSequence == 0 else {
                throw failure(
                    .framePayloadInvalid,
                    "Bridge product content acceptance is duplicated or mis-sequenced."
                )
            }
            return
        }
        guard acceptedHeader != nil, contentSequence == nextContentSequence else {
            throw failure(
                .framePayloadInvalid,
                "Bridge product content frame arrived before acceptance or out of sequence."
            )
        }
    }

    private func markTerminal() {
        nextContentSequence += 1
        terminal = true
    }

    private func resetToFrameBoundary() {
        decodingState = .prefix(frameByteLength: nil, accumulator: nil)
        accounting.transition(to: .awaitingLengthPrefix, retainedByteCount: 0)
    }

    private func poison(
        failureCode: BridgeProductFrameDecoderFailureCode,
        discardedTailByteCount: Int
    ) {
        poisoned = true
        terminal = false
        acceptedHeader = nil
        decodingState = .prefix(frameByteLength: nil, accumulator: nil)
        accounting.poison(
            failureCode: failureCode,
            discardedTailByteCount: discardedTailByteCount
        )
    }

    private func failure(
        _ code: BridgeProductFrameDecoderFailureCode,
        _ message: String
    ) -> ClassifiedFailure {
        .init(
            code: code,
            underlyingError: BridgeProductFrameCodecError.invalidFrame(message)
        )
    }

    private struct ClassifiedFailure: Error {
        let code: BridgeProductFrameDecoderFailureCode
        let underlyingError: any Error
    }

    private struct DataPayloadState {
        let contentSequence: Int
        let offsetBytes: Int
        let prefix: BridgeProductFrameByteAccumulator
        let offset: BridgeProductFrameByteAccumulator
        let payload: BridgeProductFrameByteAccumulator
    }

    private enum DecodingState {
        case prefix(
            frameByteLength: Int?,
            accumulator: BridgeProductFrameByteAccumulator?
        )
        case controlBody(
            frameTag: UInt8,
            contentSequence: Int,
            prefix: BridgeProductFrameByteAccumulator,
            body: BridgeProductFrameByteAccumulator
        )
        case dataOffset(
            contentSequence: Int,
            payloadByteLength: Int,
            prefix: BridgeProductFrameByteAccumulator,
            offset: BridgeProductFrameByteAccumulator
        )
        case dataPayload(DataPayloadState)

        var isAtFrameBoundary: Bool {
            guard case .prefix(let frameByteLength, let accumulator) = self else {
                return false
            }
            return frameByteLength == nil && accumulator == nil
        }
    }
}
