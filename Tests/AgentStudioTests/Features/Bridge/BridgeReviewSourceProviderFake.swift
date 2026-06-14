import Foundation

@testable import AgentStudio

actor BridgeReviewSourceProviderFake: BridgeReviewSourceProvider {
    var comparison: BridgeEndpointComparison
    var contentByHandleId: [String: BridgeContentLoadResult]
    var treeDescriptors: [BridgeReviewItemDescriptor]
    var itemDescriptorByPath: [String: BridgeReviewItemDescriptor]
    private let contentLoadGate: BridgeContentLoadGate?
    private let checksCancellationAfterGate: Bool
    private var contentRequests: [BridgeContentLoadRequest] = []
    private var comparisonRequests: [BridgeEndpointComparisonRequest] = []
    private var treeReadRequests: [BridgeTreeReadRequest] = []
    private var itemDescriptorRequests: [BridgeReviewItemDescriptorRequest] = []
    private var observedCancellationCount = 0
    private var finishedContentLoadCount = 0
    private var finishedContentLoadWaiters: [BridgeContentLoadWaiter] = []

    private struct BridgeContentLoadWaiter {
        let requestedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    init(
        comparison: BridgeEndpointComparison,
        contentByHandleId: [String: BridgeContentLoadResult],
        treeDescriptors: [BridgeReviewItemDescriptor] = [],
        itemDescriptorByPath: [String: BridgeReviewItemDescriptor] = [:],
        contentLoadGate: BridgeContentLoadGate? = nil,
        checksCancellationAfterGate: Bool = false
    ) {
        self.comparison = comparison
        self.contentByHandleId = contentByHandleId
        self.treeDescriptors = treeDescriptors
        self.itemDescriptorByPath = itemDescriptorByPath
        self.contentLoadGate = contentLoadGate
        self.checksCancellationAfterGate = checksCancellationAfterGate
    }

    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        request.endpoint
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        comparisonRequests.append(request)
        return BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: comparison.changedFiles
        )
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        treeReadRequests.append(request)
        return BridgeTreeReadResult(endpoint: request.endpoint, descriptors: treeDescriptors)
    }

    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    {
        itemDescriptorRequests.append(request)
        return itemDescriptorByPath[request.path]
            ?? makeBridgeReviewItemDescriptor(itemId: "item-\(request.path)", path: request.path, fileClass: .source)
    }

    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint {
        makeBridgeEndpoint(endpointId: request.checkpointId, kind: .promptCheckpoint)
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        contentRequests.append(request)
        defer {
            recordFinishedContentLoad()
        }
        await contentLoadGate?.waitUntilReleased()
        if checksCancellationAfterGate {
            do {
                try Task.checkCancellation()
            } catch {
                observedCancellationCount += 1
                throw error
            }
        }
        guard let result = contentByHandleId[request.handle.handleId] else {
            throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
        }
        guard result.handle.reviewGeneration == request.requestedGeneration else {
            throw BridgeProviderFailure.staleReviewGeneration(
                storedGeneration: result.handle.reviewGeneration,
                requestedGeneration: request.requestedGeneration
            )
        }
        return result
    }

    func recordedContentRequestsCount() -> Int {
        contentRequests.count
    }

    func recordedComparisonRequestsCount() -> Int {
        comparisonRequests.count
    }

    func setComparison(_ comparison: BridgeEndpointComparison) {
        self.comparison = comparison
    }

    func recordedTreeReadRequestsCount() -> Int {
        treeReadRequests.count
    }

    func recordedItemDescriptorRequestsCount() -> Int {
        itemDescriptorRequests.count
    }

    func recordedContentRequestsCount(handleId: String) -> Int {
        contentRequests.filter { $0.handle.handleId == handleId }.count
    }

    func recordedObservedCancellationCount() -> Int {
        observedCancellationCount
    }

    func waitForFinishedContentLoadCount(_ requestedCount: Int) async {
        guard finishedContentLoadCount < requestedCount else { return }
        await withCheckedContinuation { continuation in
            finishedContentLoadWaiters.append(
                BridgeContentLoadWaiter(requestedCount: requestedCount, continuation: continuation)
            )
        }
    }

    private func recordFinishedContentLoad() {
        finishedContentLoadCount += 1
        var pendingWaiters: [BridgeContentLoadWaiter] = []
        for waiter in finishedContentLoadWaiters {
            if finishedContentLoadCount >= waiter.requestedCount {
                waiter.continuation.resume()
            } else {
                pendingWaiters.append(waiter)
            }
        }
        finishedContentLoadWaiters = pendingWaiters
    }
}

actor BridgeContentLoadGate {
    private struct StartedLoadWaiter {
        let requestedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var startedLoadCount = 0
    private var startedLoadWaiters: [StartedLoadWaiter] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func waitUntilReleased() async {
        startedLoadCount += 1
        resumeSatisfiedStartedLoadWaiters()
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitForStartedLoadCount(_ requestedCount: Int) async {
        guard startedLoadCount < requestedCount else { return }
        await withCheckedContinuation { continuation in
            startedLoadWaiters.append(
                StartedLoadWaiter(requestedCount: requestedCount, continuation: continuation)
            )
        }
    }

    func releaseAll() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func resumeSatisfiedStartedLoadWaiters() {
        var pendingWaiters: [StartedLoadWaiter] = []
        for waiter in startedLoadWaiters {
            if startedLoadCount >= waiter.requestedCount {
                waiter.continuation.resume()
            } else {
                pendingWaiters.append(waiter)
            }
        }
        startedLoadWaiters = pendingWaiters
    }
}
