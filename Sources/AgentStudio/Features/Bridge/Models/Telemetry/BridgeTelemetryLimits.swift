enum BridgeTelemetryLimits {
    static let maxSamplesPerBatch = 64
    static let maxEncodedBatchBytes = 16 * 1024
    static let maxPendingBatchesPerPane = 2
    static let maxSwiftIngestQueueDepth = 8
    static let minimumFlushIntervalMilliseconds = 250
    static let maximumDropSummaryIntervalMilliseconds = 1000
}
