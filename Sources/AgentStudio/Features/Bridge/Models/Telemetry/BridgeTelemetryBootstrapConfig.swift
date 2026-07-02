struct BridgeTelemetryBootstrapConfig: Codable, Equatable, Sendable {
    static let packageApplyContentFetchScenario = "package_apply_content_fetch_v1"

    let enabledScopes: Set<BridgeTelemetryScope>
    let maxSamplesPerBatch: Int
    let maxEncodedBatchBytes: Int
    let minimumFlushIntervalMilliseconds: Int
    let rpcMethodName: String
    let scenario: String
    /// Wall-clock epoch (Unix milliseconds) captured natively when the pane's viewer
    /// open began. The browser subtracts this from `Date.now()` at first-interaction to
    /// produce the end-to-end cold `time_to_first_interaction` duration.
    let viewerOpenEpochUnixMillis: Int?
    /// W3C `traceparent` for the native viewer-open root span, so the browser's
    /// first-interaction sample can nest under the same trace.
    let viewerOpenTraceparent: String?

    static func enabled(
        scopes: Set<BridgeTelemetryScope>,
        scenario: String,
        viewerOpenEpochUnixMillis: Int? = nil,
        viewerOpenTraceparent: String? = nil
    ) -> Self {
        Self(
            enabledScopes: scopes,
            maxSamplesPerBatch: BridgeTelemetryLimits.maxSamplesPerBatch,
            maxEncodedBatchBytes: BridgeTelemetryLimits.maxEncodedBatchBytes,
            minimumFlushIntervalMilliseconds: BridgeTelemetryLimits.minimumFlushIntervalMilliseconds,
            rpcMethodName: "system.bridgeTelemetry",
            scenario: scenario,
            viewerOpenEpochUnixMillis: viewerOpenEpochUnixMillis,
            viewerOpenTraceparent: viewerOpenTraceparent
        )
    }
}
