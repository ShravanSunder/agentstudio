import Foundation

@testable import AgentStudio

actor CoordinatorGatedFileMetadataSource: BridgePaneProductFileMetadataProducing {
    private var didFinishOpen = false
    private var didStartOpen = false
    private var didStartUpdate = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var isOpenReleased = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var openObservedCancellation = false
    private(set) var updateObservedOpenFinished = false

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        didStartOpen = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll(keepingCapacity: false)
        if !isOpenReleased {
            await withCheckedContinuation { continuation in
                openWaiters.append(continuation)
            }
        }
        openObservedCancellation = Task.isCancelled
        didFinishOpen = true
        for waiter in finishWaiters { waiter.resume() }
        finishWaiters.removeAll(keepingCapacity: false)
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        updateObservedOpenFinished = didFinishOpen
        didStartUpdate = true
        for waiter in updateWaiters { waiter.resume() }
        updateWaiters.removeAll(keepingCapacity: false)
    }

    func cancel(subscriptionId _: String) {}

    func publish(
        status _: GitWorkingTreeStatus,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(
        changeset _: FileChangeset,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentReadPlan(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? { nil }

    func waitUntilOpenStarted() async {
        guard !didStartOpen else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilUpdateStarted() async {
        guard !didStartUpdate else { return }
        await withCheckedContinuation { continuation in
            updateWaiters.append(continuation)
        }
    }

    func releaseOpen() {
        isOpenReleased = true
        for waiter in openWaiters { waiter.resume() }
        openWaiters.removeAll(keepingCapacity: false)
    }

    func waitUntilOpenFinished() async {
        guard !didFinishOpen else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }
}

actor CoordinatorFileMetadataSource: BridgePaneProductFileMetadataProducing {
    private(set) var cancelledSubscriptionIds: [String] = []

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        try await emit(
            .sourceAccepted(
                .init(
                    source: try .init(
                        repoId: "00000000-0000-4000-8000-000000000001",
                        rootRevisionToken: "root-token-1",
                        sourceCursor: "source-cursor-1",
                        sourceId: "file-source-1",
                        subscriptionGeneration: 1,
                        worktreeId: "00000000-0000-4000-8000-000000000002"
                    )
                )
            )
        )
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {}

    func cancel(subscriptionId: String) {
        cancelledSubscriptionIds.append(subscriptionId)
    }

    func publish(
        status _: GitWorkingTreeStatus,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(
        changeset _: FileChangeset,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] { [] }

    func contentReadPlan(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? { nil }
}
