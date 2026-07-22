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
    func streamContent(
        _ request: BridgeContentStreamRequest,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamResult
}

protocol BridgeSharedReviewConstructionClient: Sendable {
    func resolveEndpoint(
        _ request: BridgeEndpointResolutionRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSourceEndpoint
    func compareEndpoints(
        _ request: BridgeEndpointComparisonRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeEndpointComparison
    func readTree(
        _ request: BridgeTreeReadRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeTreeReadResult
    func readReviewItemDescriptor(
        _ request: BridgeReviewItemDescriptorRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeReviewItemDescriptor
    func captureSharedContent(
        handles: [BridgeContentHandle],
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSharedReviewContentBacking
    func installSharedContent(
        backing: BridgeSharedReviewContentBacking,
        handles: [BridgeContentHandle]
    ) async throws
}

protocol BridgeSharedReviewConstructionSourceProvider: BridgeReviewSourceProvider,
    BridgeSharedReviewConstructionClient
{}

extension BridgeReviewSourceProvider {
    func streamContent(
        _ request: BridgeContentStreamRequest,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamResult {
        let result = try await loadContent(
            BridgeContentLoadRequest(
                handle: request.handle,
                requestedGeneration: request.requestedGeneration
            )
        )
        var offset = 0
        while offset < result.data.count {
            let endOffset = min(offset + chunkByteCount, result.data.count)
            try await emitChunk(result.data.subdata(in: offset..<endOffset))
            offset = endOffset
        }
        return BridgeContentStreamResult(
            handle: result.handle,
            byteCount: result.data.count,
            mimeType: result.mimeType,
            contentHash: result.contentHash,
            contentHashAlgorithm: result.contentHashAlgorithm
        )
    }
}
