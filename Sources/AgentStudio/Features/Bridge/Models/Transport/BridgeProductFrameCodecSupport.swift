import Foundation

enum BridgeProductFrameCodecError: Error, Equatable {
    case invalidConfiguration
    case invalidFrame(String)
    case truncatedFrame
}

enum BridgeProductFrameDecoderState: String, Equatable, Sendable {
    case awaitingLengthPrefix = "awaiting_length_prefix"
    case awaitingContentPrefix = "awaiting_content_prefix"
    case awaitingContentControlBody = "awaiting_content_control_body"
    case awaitingFrameBody = "awaiting_frame_body"
    case finished
    case poisoned
}

enum BridgeProductFrameDecoderFailureCode: String, Equatable, Sendable {
    case frameLengthInvalid = "frame_length_invalid"
    case frameLengthExceedsCeiling = "frame_length_exceeds_ceiling"
    case contentFrameTagInvalid = "content_frame_tag_invalid"
    case contentControlBodyLengthInvalid = "content_control_body_length_invalid"
    case contentControlBodyExceedsCeiling = "content_control_body_exceeds_ceiling"
    case frameDecodeInvalid = "frame_decode_invalid"
    case framePayloadInvalid = "frame_payload_invalid"
    case truncatedFrame = "truncated_frame"
}

struct BridgeProductFrameDecoderDiagnostics: Equatable, Sendable {
    let receivedByteCount: Int
    let consumedByteCount: Int
    let copiedByteCount: Int
    let retainedByteCount: Int
    let peakRetainedByteCount: Int
    let emittedFrameCount: Int
    let discardedTailByteCount: Int
    let state: BridgeProductFrameDecoderState
    let failureCode: BridgeProductFrameDecoderFailureCode?
}

struct BridgeProductFrameDecoderStorageDiagnostics: Equatable, Sendable {
    let ingressCopiedByteCount: Int
    let relocationCopiedByteCount: Int
    let allocationCount: Int
}

final class BridgeProductFrameDecoderStorageAccounting {
    private var ingressCopiedByteCount = 0
    private var relocationCopiedByteCount = 0
    private var allocationCount = 0

    var diagnostics: BridgeProductFrameDecoderStorageDiagnostics {
        .init(
            ingressCopiedByteCount: ingressCopiedByteCount,
            relocationCopiedByteCount: relocationCopiedByteCount,
            allocationCount: allocationCount
        )
    }

    func recordAllocation() {
        allocationCount += 1
    }

    func recordIngressCopy(_ byteCount: Int) {
        precondition(byteCount >= 0)
        ingressCopiedByteCount += byteCount
    }

}

final class BridgeProductFrameByteAccumulator {
    let capacity: Int
    private(set) var count = 0

    private let storageAccounting: BridgeProductFrameDecoderStorageAccounting
    private var storage: UnsafeMutableRawPointer?

    init(
        capacity: Int,
        storageAccounting: BridgeProductFrameDecoderStorageAccounting
    ) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storageAccounting = storageAccounting
        self.storage = UnsafeMutableRawPointer.allocate(
            byteCount: capacity,
            alignment: MemoryLayout<UInt8>.alignment
        )
        storageAccounting.recordAllocation()
    }

    deinit {
        storage?.deallocate()
    }

    func append(
        from source: Data,
        sourceOffset: inout Int,
        until targetByteCount: Int? = nil
    ) -> Int {
        precondition(sourceOffset >= 0 && sourceOffset <= source.count)
        let targetByteCount = targetByteCount ?? capacity
        precondition(targetByteCount >= count && targetByteCount <= capacity)
        let copiedByteCount = min(targetByteCount - count, source.count - sourceOffset)
        guard copiedByteCount > 0 else { return 0 }
        guard let storage else {
            preconditionFailure("Cannot append after accumulator ownership is transferred.")
        }

        source.withUnsafeBytes { sourceBytes in
            guard let sourceBaseAddress = sourceBytes.baseAddress else {
                preconditionFailure("Nonempty ingress bytes must expose storage.")
            }
            storage.advanced(by: count).copyMemory(
                from: sourceBaseAddress.advanced(by: sourceOffset),
                byteCount: copiedByteCount
            )
        }
        count += copiedByteCount
        sourceOffset += copiedByteCount
        storageAccounting.recordIngressCopy(copiedByteCount)
        return copiedByteCount
    }

    func byte(at offset: Int) -> UInt8 {
        precondition(offset >= 0 && offset < count)
        guard let storage else {
            preconditionFailure("Cannot read after accumulator ownership is transferred.")
        }
        return storage.load(fromByteOffset: offset, as: UInt8.self)
    }

    func readUInt32BigEndian(at offset: Int) -> Int {
        precondition(offset >= 0 && offset + 4 <= count)
        let first = UInt32(byte(at: offset))
        let second = UInt32(byte(at: offset + 1))
        let third = UInt32(byte(at: offset + 2))
        let fourth = UInt32(byte(at: offset + 3))
        return Int((first << 24) | (second << 16) | (third << 8) | fourth)
    }

    func takeData() -> Data {
        precondition(count == capacity)
        guard let storage else {
            preconditionFailure("Accumulator storage ownership can transfer only once.")
        }
        self.storage = nil
        return Data(
            bytesNoCopy: storage,
            count: count,
            deallocator: .custom { pointer, _ in pointer.deallocate() }
        )
    }
}

struct BridgeProductFrameDecoderIngressAccounting {
    private var receivedByteCount = 0
    private var consumedByteCount = 0
    private var copiedByteCount = 0
    private var retainedByteCount = 0
    private var peakRetainedByteCount = 0
    private var emittedFrameCount = 0
    private var discardedTailByteCount = 0
    private var state: BridgeProductFrameDecoderState = .awaitingLengthPrefix
    private var failureCode: BridgeProductFrameDecoderFailureCode?

    var diagnostics: BridgeProductFrameDecoderDiagnostics {
        .init(
            receivedByteCount: receivedByteCount,
            consumedByteCount: consumedByteCount,
            copiedByteCount: copiedByteCount,
            retainedByteCount: retainedByteCount,
            peakRetainedByteCount: peakRetainedByteCount,
            emittedFrameCount: emittedFrameCount,
            discardedTailByteCount: discardedTailByteCount,
            state: state,
            failureCode: failureCode
        )
    }

    mutating func recordReceivedBytes(_ byteCount: Int) {
        precondition(byteCount >= 0)
        receivedByteCount += byteCount
    }

    mutating func recordConsumedCopy(
        _ byteCount: Int,
        retainedByteCount: Int,
        state: BridgeProductFrameDecoderState
    ) {
        precondition(byteCount >= 0)
        precondition(retainedByteCount >= 0)
        consumedByteCount += byteCount
        copiedByteCount += byteCount
        self.retainedByteCount = retainedByteCount
        peakRetainedByteCount = max(peakRetainedByteCount, retainedByteCount)
        self.state = state
    }

    mutating func transition(
        to state: BridgeProductFrameDecoderState,
        retainedByteCount: Int
    ) {
        precondition(retainedByteCount >= 0)
        self.retainedByteCount = retainedByteCount
        peakRetainedByteCount = max(peakRetainedByteCount, retainedByteCount)
        self.state = state
    }

    mutating func commitEmittedFrames(_ frameCount: Int) {
        precondition(frameCount >= 0)
        emittedFrameCount += frameCount
    }

    mutating func finish() {
        precondition(retainedByteCount == 0)
        state = .finished
    }

    mutating func poison(
        failureCode: BridgeProductFrameDecoderFailureCode,
        discardedTailByteCount: Int
    ) {
        precondition(discardedTailByteCount >= 0)
        self.discardedTailByteCount += discardedTailByteCount
        retainedByteCount = 0
        state = .poisoned
        self.failureCode = failureCode
    }
}

enum BridgeProductFrameCodecSupport {
    static func appendUInt32BigEndian(_ value: Int, to data: inout Data) throws {
        guard value >= 0, value <= Int(UInt32.max) else {
            throw BridgeProductFrameCodecError.invalidFrame("Frame length exceeds u32.")
        }
        let unsignedValue = UInt32(value)
        data.append(UInt8((unsignedValue >> 24) & 0xff))
        data.append(UInt8((unsignedValue >> 16) & 0xff))
        data.append(UInt8((unsignedValue >> 8) & 0xff))
        data.append(UInt8(unsignedValue & 0xff))
    }

    static func readUInt32BigEndian(from data: Data, at offset: Int) -> Int {
        let first = UInt32(data[data.index(data.startIndex, offsetBy: offset)])
        let second = UInt32(data[data.index(data.startIndex, offsetBy: offset + 1)])
        let third = UInt32(data[data.index(data.startIndex, offsetBy: offset + 2)])
        let fourth = UInt32(data[data.index(data.startIndex, offsetBy: offset + 3)])
        return Int((first << 24) | (second << 16) | (third << 8) | fourth)
    }

    static func decodeStrictJSON<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        from data: Data
    ) throws -> DecodedValue {
        do {
            return try BridgeProductStrictJSON.decode(type, from: data)
        } catch {
            throw BridgeProductFrameCodecError.invalidFrame("Frame JSON does not match its closed contract.")
        }
    }
}
