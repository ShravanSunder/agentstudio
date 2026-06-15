struct BridgeTelemetryQueue: Sendable {
    private(set) var pendingBatchCount = 0
    private(set) var droppedBatchCount = 0
    private(set) var lastDropReason: BridgeTelemetryDropReason?

    mutating func admitBatch() -> BridgeTelemetryDropReason? {
        guard pendingBatchCount < BridgeTelemetryLimits.maxPendingBatchesPerPane else {
            droppedBatchCount += 1
            lastDropReason = .queueSaturated
            return .queueSaturated
        }
        pendingBatchCount += 1
        return nil
    }

    mutating func finishBatch() {
        pendingBatchCount = max(0, pendingBatchCount - 1)
    }

    var state: BridgeTelemetrySinkState {
        BridgeTelemetrySinkState(
            pendingBatchCount: pendingBatchCount,
            droppedBatchCount: droppedBatchCount,
            lastDropReason: lastDropReason
        )
    }
}
