struct BridgeTelemetryBootstrapConfig: Codable, Equatable, Sendable {
    static let packageApplyContentFetchScenario = "package_apply_content_fetch_v1"

    let enabledScopes: Set<BridgeTelemetryScope>
    let maxSamplesPerBatch: Int
    let maxEncodedBatchBytes: Int
    let minimumFlushIntervalMilliseconds: Int
    let rpcMethodName: String
    let scenario: String

    static func enabled(
        scopes: Set<BridgeTelemetryScope>,
        scenario: String
    ) -> Self {
        Self(
            enabledScopes: scopes,
            maxSamplesPerBatch: BridgeTelemetryLimits.maxSamplesPerBatch,
            maxEncodedBatchBytes: BridgeTelemetryLimits.maxEncodedBatchBytes,
            minimumFlushIntervalMilliseconds: BridgeTelemetryLimits.minimumFlushIntervalMilliseconds,
            rpcMethodName: "system.bridgeTelemetry",
            scenario: scenario
        )
    }
}
