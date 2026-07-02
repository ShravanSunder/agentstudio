struct BridgeTelemetryQueue: Sendable {
    private(set) var pendingBatchCount = 0
    private(set) var droppedBatchCount = 0
    private(set) var lastDropReason: BridgeTelemetryDropReason?

    mutating func admitBatch(priority: BridgeTelemetryPriority) -> BridgeTelemetryDropReason? {
        guard pendingBatchCount < pendingBatchLimit(for: priority) else {
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

    private func pendingBatchLimit(for priority: BridgeTelemetryPriority) -> Int {
        switch priority {
        case .hot, .warm:
            BridgeTelemetryLimits.maxPrioritizedPendingBatchesPerPane
        case .cold, .bestEffort:
            BridgeTelemetryLimits.maxPendingBatchesPerPane
        }
    }
}
