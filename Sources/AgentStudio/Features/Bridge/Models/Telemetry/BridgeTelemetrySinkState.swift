struct BridgeTelemetrySinkState: Equatable, Sendable {
    let pendingBatchCount: Int
    let droppedBatchCount: Int
    let lastDropReason: BridgeTelemetryDropReason?

    static let empty = Self(
        pendingBatchCount: 0,
        droppedBatchCount: 0,
        lastDropReason: nil
    )
}
