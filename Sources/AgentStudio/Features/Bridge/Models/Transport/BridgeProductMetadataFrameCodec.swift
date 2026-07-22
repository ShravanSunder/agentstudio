import Foundation

enum BridgeProductMetadataFrameCodec {
    private static let lengthPrefixByteCount = 4

    static func encode(_ frame: BridgeProductMetadataFrame) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let frameData = try encoder.encode(frame)
        guard
            !frameData.isEmpty,
            frameData.count <= BridgeProductWireContract.maximumMetadataFrameBytes
        else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product metadata frame exceeds its byte ceiling."
            )
        }
        var encodedFrame = Data(capacity: lengthPrefixByteCount + frameData.count)
        try BridgeProductFrameCodecSupport.appendUInt32BigEndian(frameData.count, to: &encodedFrame)
        encodedFrame.append(frameData)
        return encodedFrame
    }
}

final class BridgeProductMetadataFrameDecoder {
    private static let lengthPrefixByteCount = 4

    private let maximumFrameBytes: Int
    private var accounting = BridgeProductFrameDecoderIngressAccounting()
    private let storageAccounting = BridgeProductFrameDecoderStorageAccounting()
    private var decodingState: DecodingState = .lengthPrefix(nil)
    private var finished = false
    private var poisoned = false

    var diagnostics: BridgeProductFrameDecoderDiagnostics {
        accounting.diagnostics
    }

    var storageDiagnostics: BridgeProductFrameDecoderStorageDiagnostics {
        storageAccounting.diagnostics
    }

    init(maximumFrameBytes: Int = BridgeProductWireContract.maximumMetadataFrameBytes) throws {
        guard maximumFrameBytes > 0,
            maximumFrameBytes <= BridgeProductWireContract.maximumMetadataFrameBytes
        else {
            throw BridgeProductFrameCodecError.invalidConfiguration
        }
        self.maximumFrameBytes = maximumFrameBytes
    }

    func append(_ chunk: Data) throws -> [BridgeProductMetadataFrame] {
        guard !poisoned else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product metadata decoder is unusable after a framing failure."
            )
        }
        guard !finished else {
            throw BridgeProductFrameCodecError.invalidFrame(
                "Bridge product metadata decoder cannot accept bytes after finish."
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
                "Bridge product metadata decoder is unusable after a framing failure."
            )
        }
        guard !finished else { return }
        guard decodingState.isAtFrameBoundary else {
            poison(
                failureCode: .truncatedFrame,
                discardedTailByteCount: diagnostics.retainedByteCount
            )
            throw BridgeProductFrameCodecError.truncatedFrame
        }
        finished = true
        accounting.finish()
    }

    private func appendValidated(_ chunk: Data) throws -> [BridgeProductMetadataFrame] {
        guard !chunk.isEmpty else { return [] }
        var decodedFrames: [BridgeProductMetadataFrame] = []
        var sourceOffset = 0

        while sourceOffset < chunk.count {
            switch decodingState {
            case .lengthPrefix(let existingPrefix):
                let prefix =
                    existingPrefix
                    ?? BridgeProductFrameByteAccumulator(
                        capacity: Self.lengthPrefixByteCount,
                        storageAccounting: storageAccounting
                    )
                let copiedByteCount = prefix.append(from: chunk, sourceOffset: &sourceOffset)
                accounting.recordConsumedCopy(
                    copiedByteCount,
                    retainedByteCount: prefix.count,
                    state: .awaitingLengthPrefix
                )
                guard prefix.count == prefix.capacity else {
                    decodingState = .lengthPrefix(prefix)
                    continue
                }
                try admitFrameLength(from: prefix)

            case .frameBody(let frameByteLength, let prefix, let body):
                let copiedByteCount = body.append(from: chunk, sourceOffset: &sourceOffset)
                accounting.recordConsumedCopy(
                    copiedByteCount,
                    retainedByteCount: prefix.count + body.count,
                    state: .awaitingFrameBody
                )
                guard body.count == frameByteLength else { continue }

                do {
                    decodedFrames.append(
                        try BridgeProductFrameCodecSupport.decodeStrictJSON(
                            BridgeProductMetadataFrame.self,
                            from: body.takeData()
                        )
                    )
                } catch {
                    throw ClassifiedFailure(code: .frameDecodeInvalid, underlyingError: error)
                }
                decodingState = .lengthPrefix(nil)
                accounting.transition(to: .awaitingLengthPrefix, retainedByteCount: 0)
            }
        }
        return decodedFrames
    }

    private func admitFrameLength(from prefix: BridgeProductFrameByteAccumulator) throws {
        let frameByteLength = prefix.readUInt32BigEndian(at: 0)
        guard frameByteLength > 0 else {
            throw ClassifiedFailure(
                code: .frameLengthInvalid,
                underlyingError: BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product metadata frame length is invalid."
                )
            )
        }
        guard frameByteLength <= maximumFrameBytes else {
            throw ClassifiedFailure(
                code: .frameLengthExceedsCeiling,
                underlyingError: BridgeProductFrameCodecError.invalidFrame(
                    "Bridge product metadata frame exceeds its byte ceiling."
                )
            )
        }
        let body = BridgeProductFrameByteAccumulator(
            capacity: frameByteLength,
            storageAccounting: storageAccounting
        )
        decodingState = .frameBody(
            frameByteLength: frameByteLength,
            prefix: prefix,
            body: body
        )
        accounting.transition(to: .awaitingFrameBody, retainedByteCount: prefix.count)
    }

    private func poison(
        failureCode: BridgeProductFrameDecoderFailureCode,
        discardedTailByteCount: Int
    ) {
        poisoned = true
        decodingState = .lengthPrefix(nil)
        accounting.poison(
            failureCode: failureCode,
            discardedTailByteCount: discardedTailByteCount
        )
    }

    private struct ClassifiedFailure: Error {
        let code: BridgeProductFrameDecoderFailureCode
        let underlyingError: any Error
    }

    private enum DecodingState {
        case lengthPrefix(BridgeProductFrameByteAccumulator?)
        case frameBody(
            frameByteLength: Int,
            prefix: BridgeProductFrameByteAccumulator,
            body: BridgeProductFrameByteAccumulator
        )

        var isAtFrameBoundary: Bool {
            guard case .lengthPrefix(let prefix) = self else { return false }
            return prefix == nil
        }
    }
}
