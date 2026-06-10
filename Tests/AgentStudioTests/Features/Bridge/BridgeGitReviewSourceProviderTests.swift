import Foundation
import Testing

@testable import AgentStudio

struct BridgeGitReviewSourceProviderTests {
    @Test("git review source provider forwards through backend-neutral client")
    func gitReviewSourceProviderForwardsThroughBackendNeutralClient() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100
        )
        let comparison = BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [changedFile]
        )
        let client = BridgeGitReviewDataClientFake(comparison: comparison)
        let provider = BridgeGitReviewSourceProvider(client: client)
        let query = makeBridgeReviewQuery()

        let result = try await provider.compareEndpoints(
            BridgeEndpointComparisonRequest(
                query: query,
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                reviewGeneration: 1
            )
        )

        #expect(result == comparison)
        #expect(await client.recordedComparisonRequestsCount() == 1)
    }

    @Test("git review source provider preserves content handle identity")
    func gitReviewSourceProviderPreservesContentHandleIdentity() async throws {
        let handle = makeBridgeContentHandle(itemId: "item-source", role: .head, reviewGeneration: 2)
        let expectedResult = makeContentResult(handle: handle, data: "content")
        let client = BridgeGitReviewDataClientFake(contentResult: expectedResult)
        let provider = BridgeGitReviewSourceProvider(client: client)

        let result = try await provider.loadContent(
            BridgeContentLoadRequest(handle: handle, requestedGeneration: 2)
        )

        #expect(result == expectedResult)
        #expect(await client.recordedContentRequestsCount() == 1)
    }
}

private actor BridgeGitReviewDataClientFake: BridgeGitReviewDataClient {
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
