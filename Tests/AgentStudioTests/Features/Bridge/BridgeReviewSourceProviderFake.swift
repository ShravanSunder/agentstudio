import Foundation

@testable import AgentStudio

actor BridgeReviewSourceProviderFake: BridgeReviewSourceProvider {
    var comparison: BridgeEndpointComparison
    var contentByHandleId: [String: BridgeContentLoadResult]

    init(
        comparison: BridgeEndpointComparison,
        contentByHandleId: [String: BridgeContentLoadResult]
    ) {
        self.comparison = comparison
        self.contentByHandleId = contentByHandleId
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        request.endpoint
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: comparison.changedFiles
        )
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        BridgeTreeReadResult(endpoint: request.endpoint, descriptors: [])
    }

    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    {
        makeBridgeReviewItemDescriptor(itemId: "item-\(request.path)", path: request.path, fileClass: .source)
    }

    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint {
        makeBridgeEndpoint(endpointId: request.checkpointId, kind: .promptCheckpoint)
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        guard let result = contentByHandleId[request.handle.handleId] else {
            throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
        }
        guard result.handle.reviewGeneration == request.requestedGeneration else {
            throw BridgeProviderFailure.staleReviewGeneration(
                expected: result.handle.reviewGeneration,
                actual: request.requestedGeneration
            )
        }
        return result
    }
}
