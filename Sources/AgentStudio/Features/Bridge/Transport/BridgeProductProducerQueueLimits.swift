import Foundation

enum BridgeProductProducerQueueLimitsError: Error, Equatable, Sendable {
    case invalidContentProducerResidueLimit
    case invalidMaximumEncodedFrameByteCount
    case invalidMaximumQueuedByteCount
    case invalidMaximumQueuedFrameCount
    case invalidTerminalFrameReserve
    case contentProducerResidueLimitExceedsProductContract
    case maximumEncodedFrameExceedsQueue
    case maximumEncodedFrameExceedsWireContract
    case maximumQueuedBytesExceedWireContract
    case maximumQueuedFramesExceedWireContract
}

struct BridgeProductProducerQueueLimits: Equatable, Sendable {
    static let maximumProductContentProducerLifecycleResidueCount = 16
    static let maximumProductEncodedFrameByteCount =
        max(
            BridgeProductWireContract.maximumMetadataFrameBytes,
            BridgeProductWireContract.maximumContentFrameBytes
        ) + MemoryLayout<UInt32>.size

    static let productContract = Self(
        maximumContentProducerLifecycleResidueCount:
            maximumProductContentProducerLifecycleResidueCount,
        maximumQueuedFrameCount: BridgeProductWireContract.maximumQueuedStreamFrames,
        maximumQueuedByteCount: BridgeProductWireContract.maximumQueuedStreamBytes,
        maximumEncodedFrameByteCount: maximumProductEncodedFrameByteCount,
        terminalFrameReserve: BridgeProductWireContract.terminalFrameReserve,
        validated: ()
    )

    let maximumContentProducerLifecycleResidueCount: Int
    let maximumQueuedFrameCount: Int
    let maximumQueuedByteCount: Int
    let maximumEncodedFrameByteCount: Int
    let terminalFrameReserve: Int

    init(
        maximumContentProducerLifecycleResidueCount: Int =
            Self.maximumProductContentProducerLifecycleResidueCount,
        maximumQueuedFrameCount: Int,
        maximumQueuedByteCount: Int,
        maximumEncodedFrameByteCount: Int,
        terminalFrameReserve: Int
    ) throws {
        guard maximumContentProducerLifecycleResidueCount > 0 else {
            throw BridgeProductProducerQueueLimitsError
                .invalidContentProducerResidueLimit
        }
        guard
            maximumContentProducerLifecycleResidueCount
                <= Self.maximumProductContentProducerLifecycleResidueCount
        else {
            throw BridgeProductProducerQueueLimitsError
                .contentProducerResidueLimitExceedsProductContract
        }
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
        self.maximumContentProducerLifecycleResidueCount =
            maximumContentProducerLifecycleResidueCount
        self.maximumQueuedFrameCount = maximumQueuedFrameCount
        self.maximumQueuedByteCount = maximumQueuedByteCount
        self.maximumEncodedFrameByteCount = maximumEncodedFrameByteCount
        self.terminalFrameReserve = terminalFrameReserve
    }

    private init(
        maximumContentProducerLifecycleResidueCount: Int,
        maximumQueuedFrameCount: Int,
        maximumQueuedByteCount: Int,
        maximumEncodedFrameByteCount: Int,
        terminalFrameReserve: Int,
        validated _: Void
    ) {
        self.maximumContentProducerLifecycleResidueCount =
            maximumContentProducerLifecycleResidueCount
        self.maximumQueuedFrameCount = maximumQueuedFrameCount
        self.maximumQueuedByteCount = maximumQueuedByteCount
        self.maximumEncodedFrameByteCount = maximumEncodedFrameByteCount
        self.terminalFrameReserve = terminalFrameReserve
    }
}
