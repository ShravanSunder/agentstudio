enum BridgeTelemetrySlice: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case diffStatus = "diff_status"
    case diffPackageMetadata = "diff_package_metadata"
    case diffPackageDelta = "diff_package_delta"
    case diffFiles = "diff_files"
    case reviewThreads = "review_threads"
    case reviewViewedFiles = "review_viewed_files"
    case connectionHealth = "connection_health"
    case commandAcks = "command_acks"
    case reviewRPC = "review_rpc"
    case contentFetch = "content_fetch"
    case telemetryBatch = "telemetry_batch"
    case telemetryIngest = "telemetry_ingest"
    case telemetryDrop = "telemetry_drop"
    case unknown
}
