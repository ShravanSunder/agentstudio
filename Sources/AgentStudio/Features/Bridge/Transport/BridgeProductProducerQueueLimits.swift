import Foundation

enum BridgeProductProducerQueueLimitsError: Error, Equatable, Sendable {
    case invalidMaximumEncodedFrameByteCount
    case invalidMaximumQueuedByteCount
    case invalidMaximumQueuedFrameCount
    case invalidTerminalFrameReserve
    case maximumEncodedFrameExceedsQueue
    case maximumEncodedFrameExceedsWireContract
    case maximumQueuedBytesExceedWireContract
    case maximumQueuedFramesExceedWireContract
}

struct BridgeProductProducerQueueLimits: Equatable, Sendable {
    static let maximumProductEncodedFrameByteCount =
        max(
            BridgeProductWireContract.maximumMetadataFrameBytes,
            BridgeProductWireContract.maximumContentFrameBytes
        ) + MemoryLayout<UInt32>.size

    static let productContract = Self(
        maximumQueuedFrameCount: BridgeProductWireContract.maximumQueuedStreamFrames,
        maximumQueuedByteCount: BridgeProductWireContract.maximumQueuedStreamBytes,
        maximumEncodedFrameByteCount: maximumProductEncodedFrameByteCount,
        terminalFrameReserve: BridgeProductWireContract.terminalFrameReserve,
        validated: ()
    )

    let maximumQueuedFrameCount: Int
    let maximumQueuedByteCount: Int
    let maximumEncodedFrameByteCount: Int
    let terminalFrameReserve: Int

    init(
        maximumQueuedFrameCount: Int,
        maximumQueuedByteCount: Int,
        maximumEncodedFrameByteCount: Int,
        terminalFrameReserve: Int
    ) throws {
        guard maximumQueuedFrameCount > 0 else {
            throw BridgeProductProducerQueueLimitsError.invalidMaximumQueuedFrameCount
        }
        guard maximumQueuedFrameCount <= BridgeProductWireContract.maximumQueuedStreamFrames else {
            throw BridgeProductProducerQueueLimitsError.maximumQueuedFramesExceedWireContract
        }
        guard maximumQueuedByteCount > 0 else {
            throw BridgeProductProducerQueueLimitsError.invalidMaximumQueuedByteCount
        }
        guard maximumQueuedByteCount <= BridgeProductWireContract.maximumQueuedStreamBytes else {
            throw BridgeProductProducerQueueLimitsError.maximumQueuedBytesExceedWireContract
        }
        guard maximumEncodedFrameByteCount > 0 else {
            throw BridgeProductProducerQueueLimitsError.invalidMaximumEncodedFrameByteCount
        }
        guard maximumEncodedFrameByteCount <= Self.maximumProductEncodedFrameByteCount else {
            throw BridgeProductProducerQueueLimitsError.maximumEncodedFrameExceedsWireContract
        }
        guard maximumEncodedFrameByteCount <= maximumQueuedByteCount else {
            throw BridgeProductProducerQueueLimitsError.maximumEncodedFrameExceedsQueue
        }
        guard terminalFrameReserve == BridgeProductWireContract.terminalFrameReserve,
            terminalFrameReserve < maximumQueuedFrameCount
        else {
            throw BridgeProductProducerQueueLimitsError.invalidTerminalFrameReserve
        }
        self.maximumQueuedFrameCount = maximumQueuedFrameCount
        self.maximumQueuedByteCount = maximumQueuedByteCount
        self.maximumEncodedFrameByteCount = maximumEncodedFrameByteCount
        self.terminalFrameReserve = terminalFrameReserve
    }

    private init(
        maximumQueuedFrameCount: Int,
        maximumQueuedByteCount: Int,
        maximumEncodedFrameByteCount: Int,
        terminalFrameReserve: Int,
        validated _: Void
    ) {
        self.maximumQueuedFrameCount = maximumQueuedFrameCount
        self.maximumQueuedByteCount = maximumQueuedByteCount
        self.maximumEncodedFrameByteCount = maximumEncodedFrameByteCount
        self.terminalFrameReserve = terminalFrameReserve
    }
}
