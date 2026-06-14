import Foundation

/// Bridge-owned review data contract.
///
/// Bridge keeps this protocol because review queries, source endpoints,
/// checkpoints, content handles, review generations, package identity, and
/// deltas are Bridge concepts. A backend may be called directly only when its
/// public DTOs exactly match these contracts; otherwise use one thin mapper.
protocol BridgeReviewSourceProvider: Sendable {
    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint
    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison
    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult
    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint
    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult
}
