import AgentStudioInfrastructure
import Foundation

@testable import AgentStudioBridge

actor BridgeGitReviewDataClientFake: BridgeGitReviewDataClient, BridgeSharedReviewConstructionClient {
    func reviewComparisonTargets() async throws -> BridgeReviewComparisonTargetCatalog? {
        nil
    }

    func captureContributionComparison(_ request: BridgeContributionComparisonRequest) async throws
        -> BridgeContributionComparisonCapture
    {
        throw BridgeProviderFailure.providerFailed(message: "Contribution capture not configured")
    }

    private let comparison: BridgeEndpointComparison?
    private let contentResult: BridgeContentLoadResult?
    private var comparisonRequests: [BridgeEndpointComparisonRequest] = []
    private var contentRequests: [BridgeContentLoadRequest] = []
    private var sharedComparisonRequests: [BridgeEndpointComparisonRequest] = []
    private var sharedEndpointResolutionRequests: [BridgeEndpointResolutionRequest] = []

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

    func resolveEndpoint(
        _ request: BridgeEndpointResolutionRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSourceEndpoint {
        _ = freshnessKey
        sharedEndpointResolutionRequests.append(request)
        return request.endpoint
    }

    func compareEndpoints(
        _ request: BridgeEndpointComparisonRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeEndpointComparison {
        _ = freshnessKey
        sharedComparisonRequests.append(request)
        if let comparison {
            return comparison
        }
        return BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: []
        )
    }

    func readTree(
        _ request: BridgeTreeReadRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeTreeReadResult {
        _ = freshnessKey
        return BridgeTreeReadResult(endpoint: request.endpoint, descriptors: [])
    }

    func readReviewItemDescriptor(
        _ request: BridgeReviewItemDescriptorRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeReviewItemDescriptor {
        _ = freshnessKey
        return makeBridgeReviewItemDescriptor(
            itemId: "item-\(request.path)",
            path: request.path,
            fileClass: .source
        )
    }

    func captureSharedContent(
        handles: [BridgeContentHandle],
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSharedReviewContentBacking {
        _ = handles
        _ = freshnessKey
        return BridgeSharedReviewContentBacking(
            artifactIdentity: UUIDv7.generate(),
            directoryURL: FileManager.default.temporaryDirectory.appending(
                path: "bridge-review-data-client-fake-\(UUIDv7.generate().uuidString)"
            ),
            sourceByIdentity: [:],
            capturedByteCount: 0
        )
    }

    func installSharedContent(
        backing: BridgeSharedReviewContentBacking,
        handles: [BridgeContentHandle]
    ) async throws {
        _ = backing
        _ = handles
    }

    func recordedSharedComparisonRequestsCount() -> Int {
        sharedComparisonRequests.count
    }

    func recordedSharedEndpointResolutionRequestsCount() -> Int {
        sharedEndpointResolutionRequests.count
    }
}
