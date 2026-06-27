@testable import AgentStudio

actor BridgeGitReviewDataClientFake: BridgeGitReviewDataClient {
    private let comparison: BridgeEndpointComparison?
    private let contentResult: BridgeContentLoadResult?
    private var comparisonRequests: [BridgeEndpointComparisonRequest] = []
    private var contentRequests: [BridgeContentLoadRequest] = []

    init(
        comparison: BridgeEndpointComparison? = nil,
        contentResult: BridgeContentLoadResult? = nil
    ) {
        self.comparison = comparison
        self.contentResult = contentResult
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        request.endpoint
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        comparisonRequests.append(request)
        if let comparison {
            return comparison
        }
        return BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: []
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
        contentRequests.append(request)
        if let contentResult {
            return contentResult
        }
        throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
    }

    func recordedComparisonRequestsCount() -> Int {
        comparisonRequests.count
    }

    func recordedContentRequestsCount() -> Int {
        contentRequests.count
    }
}
