import Foundation

protocol BridgeGitReviewDataClient: Sendable {
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

extension BridgeGitReviewDataClient {
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

actor BridgeGitReviewSourceProvider: BridgeReviewSourceProvider {
    private let client: any BridgeGitReviewDataClient

    init(client: any BridgeGitReviewDataClient) {
        self.client = client
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        try await client.resolveEndpoint(request)
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        try await client.compareEndpoints(request)
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        try await client.readTree(request)
    }

    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    {
        try await client.readReviewItemDescriptor(request)
    }

    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint {
        try await client.resolveCheckpointEndpoint(request)
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        try await client.loadContent(request)
    }

    func streamContent(
        _ request: BridgeContentStreamRequest,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamResult {
        try await client.streamContent(
            request,
            chunkByteCount: chunkByteCount,
            emitChunk: emitChunk
        )
    }
}
