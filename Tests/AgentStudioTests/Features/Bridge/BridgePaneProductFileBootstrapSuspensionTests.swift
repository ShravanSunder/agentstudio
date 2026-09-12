import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge pane product File bootstrap suspension", .serialized)
struct BridgePaneProductFileBootstrapSuspensionTests {
    @Test(
        "foreground return reopens File source interrupted after acceptance before enumeration",
        .timeLimit(.minutes(1)),
        arguments: FileBootstrapSuspensionOrdering.allCases
    )
    func foregroundReturnReopensAcceptedButIncompleteFileSource(
        _ ordering: FileBootstrapSuspensionOrdering
    ) async throws {
        // Arrange
        let activityCoordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let fixture = try ProductFileSourceFixture(
            fileCount: 3,
            productAdmission: harness.productAdmission
        )
        defer { fixture.remove() }
        let lifecycleRecorder = FileBootstrapLifecycleRecorder()
        let snapshotBuilderGate = FileBootstrapSnapshotBuilderGate(
            lifecycleRecorder: lifecycleRecorder
        )
        let (sourceAcceptedEvents, sourceAcceptedContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(2))
        defer { sourceAcceptedContinuation.finish() }
        var sourceAcceptedIterator = sourceAcceptedEvents.makeAsyncIterator()
        let fileMetadataSource = fixture.makeSource(
            sourceAcceptedObserver: { _ in _ = sourceAcceptedContinuation.yield() },
            sharedSnapshotBuilder: { request, preparation, publisher in
                try await snapshotBuilderGate.build(
                    request: request,
                    preparation: preparation,
                    publisher: publisher
                )
            }
        )
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: fileMetadataSource,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: activityCoordinator.workAdmissionSource,
            lifecycleTraceRecorder: lifecycleRecorder
        )
        do {
            let initialSource = try await admitFileBootstrapSubscription(
                FileBootstrapSubscriptionAdmissionProps(
                    coordinator: coordinator,
                    fixture: fixture,
                    harness: harness,
                    lease: lease,
                    pump: pump
                )
            )
            _ = await sourceAcceptedIterator.next()
            await snapshotBuilderGate.waitUntilStarted(invocation: 1)

            // Act
            activityCoordinator.applyActivity(.loadedHidden)
            switch ordering {
            case .cancelBuilderDuringSuspension:
                let suspension = Task { await coordinator.suspendForegroundWork() }
                await snapshotBuilderGate.waitUntilCancelled(invocation: 1)
                await snapshotBuilderGate.release(invocation: 1)
                await suspension.value
            case .completeBuilderAfterActivityInvalidationBeforeSuspension:
                await snapshotBuilderGate.release(invocation: 1)
                await lifecycleRecorder.waitForFileProducerFinished(count: 1)
                #expect(!(await snapshotBuilderGate.observedCancellation(invocation: 1)))
                await coordinator.suspendForegroundWork()
            }
            await lifecycleRecorder.waitForFileProducerFinished(count: 1)
            await expectInterruptedFileSourceReleased(fileMetadataSource)

            activityCoordinator.applyActivity(.foreground)
            await coordinator.resumeForegroundWork()
            await lifecycleRecorder.waitForFileProducerStarted(count: 2)
            try #require(
                await lifecycleRecorder.waitForResumeDispatch() == .sourceReopen,
                "Foreground return must reopen an accepted File source whose initial enumeration was cancelled"
            )
            let resumedTree = try await pullResumedFileTree(from: pump)
            await lifecycleRecorder.waitForFileProducerFinished(count: 2)

            // Assert
            #expect(
                resumedTree.source.subscriptionGeneration
                    > initialSource.subscriptionGeneration
            )
            #expect(resumedTree.finalWindow.finalWindow)
            #expect(resumedTree.finalWindow.totalRowCount == 3)
            #expect(resumedTree.rows.contains { $0.path == fixture.demandedPath })
            #expect(
                await fileMetadataSource.diagnosticSnapshot()
                    == .init(
                        descriptorCount: 0,
                        inFlightDescriptorCount: 0,
                        manifestRowCount: 3,
                        subscriptionCount: 1
                    )
            )
        } catch {
            await snapshotBuilderGate.release(invocation: 1)
            await coordinator.uninstall(lease: lease)
            _ = await pump.cancel()
            throw error
        }

        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }
}

private func expectInterruptedFileSourceReleased(
    _ source: BridgePaneProductFileMetadataSource
) async {
    #expect(
        await source.diagnosticSnapshot()
            == .init(
                descriptorCount: 0,
                inFlightDescriptorCount: 0,
                manifestRowCount: 0,
                subscriptionCount: 0
            )
    )
}

private struct FileBootstrapSubscriptionAdmissionProps {
    let coordinator: BridgePaneProductMetadataCoordinator
    let fixture: ProductFileSourceFixture
    let harness: BridgeProductSessionLifecycleHarness
    let lease: BridgeProductProducerLease
    let pump: BridgeProductSchemeFramePump
}

private func admitFileBootstrapSubscription(
    _ props: FileBootstrapSubscriptionAdmissionProps
) async throws -> BridgeProductFileSourceIdentity {
    await props.coordinator.install(
        request: try coordinatorMetadataStreamRequest(),
        lease: props.lease,
        productAdmission: props.harness.productAdmission.context,
        session: props.harness.session
    )
    let openRequest = try fileBootstrapSubscriptionOpenRequest(fixture: props.fixture)
    let controlToken = try #require(
        controlExecutionToken(try await props.harness.begin(openRequest))
    )
    #expect(await props.harness.session.claimControlProviderDispatch(token: controlToken))
    let openResponse = try BridgeProductControlResponse.subscriptionOpenAccepted(
        correlating: openRequest,
        interestSha256: BridgeProductSubscriptionInterestState.fileMetadata(
            interests: [],
            pathScope: []
        ).sha256Hex()
    )
    let openEffect = try await props.harness.session.completeControl(
        token: controlToken,
        exactResponseBytes: try JSONEncoder().encode(openResponse)
    )
    let acceptedFrame = try await pullMetadataFrame(from: props.pump)
    await props.coordinator.apply(
        openEffect,
        productAdmission: props.harness.productAdmission.context
    )
    let initialSourceFrame = try await pullMetadataFrame(from: props.pump)
    await props.harness.session.settleControlProviderDispatch(token: controlToken)
    guard case .subscriptionAccepted = acceptedFrame,
        case .subscriptionData(let initialSourceData) = initialSourceFrame,
        let initialFileEvent = initialSourceData.data.fileMetadataEvent,
        case .sourceAccepted(let initialSourceAccepted) = initialFileEvent
    else {
        Issue.record("Expected File subscription acceptance followed by source acceptance")
        throw FileBootstrapSuspensionTestError.expectedSourceAcceptance
    }
    return initialSourceAccepted.source
}

enum FileBootstrapSuspensionOrdering: CaseIterable, CustomTestStringConvertible, Sendable {
    case cancelBuilderDuringSuspension
    case completeBuilderAfterActivityInvalidationBeforeSuspension

    var testDescription: String {
        switch self {
        case .cancelBuilderDuringSuspension:
            "suspension cancels the held builder"
        case .completeBuilderAfterActivityInvalidationBeforeSuspension:
            "builder completes after activity invalidation before suspension"
        }
    }
}

private struct ResumedFileTree {
    let source: BridgeProductFileSourceIdentity
    let finalWindow: BridgeProductFileTreeWindowEvent
    let rows: [BridgeProductFileTreeRow]
}

private actor FileBootstrapSnapshotBuilderGate {
    private var cancellationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var cancelledInvocations: Set<Int> = []
    private(set) var invocationCount = 0
    private var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releasedInvocations: Set<Int> = []
    private var startWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var startedInvocations: Set<Int> = []
    private let lifecycleRecorder: FileBootstrapLifecycleRecorder

    init(lifecycleRecorder: FileBootstrapLifecycleRecorder) {
        self.lifecycleRecorder = lifecycleRecorder
    }

    func build(
        request: BridgeWorktreeFileMaterializationRequest,
        preparation: BridgeSharedFileSnapshotPreparation,
        publisher: BridgeSharedFileSnapshotPublisher
    ) async throws -> BridgeSharedFileSnapshotCompletion {
        invocationCount += 1
        let invocation = invocationCount
        startedInvocations.insert(invocation)
        for waiter in startWaiters.removeValue(forKey: invocation) ?? [] {
            waiter.resume()
        }
        if invocation == 2 {
            await lifecycleRecorder.recordResumeBuilderStarted()
        }
        if invocation == 1 {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if releasedInvocations.contains(invocation) {
                        continuation.resume()
                    } else {
                        releaseContinuations[invocation] = continuation
                    }
                }
            } onCancel: {
                Task { await self.recordCancellation(invocation: invocation) }
            }
            try Task.checkCancellation()
        }
        return try await BridgeWorktreeFileMaterializer.buildSharedSnapshot(
            request: request,
            preparation: preparation,
            publisher: publisher
        )
    }

    func release(invocation: Int) {
        releasedInvocations.insert(invocation)
        releaseContinuations.removeValue(forKey: invocation)?.resume()
    }

    func observedCancellation(invocation: Int) -> Bool {
        cancelledInvocations.contains(invocation)
    }

    func waitUntilCancelled(invocation: Int) async {
        guard !cancelledInvocations.contains(invocation) else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters[invocation, default: []].append(continuation)
        }
    }

    func waitUntilStarted(invocation: Int) async {
        guard !startedInvocations.contains(invocation) else { return }
        await withCheckedContinuation { continuation in
            startWaiters[invocation, default: []].append(continuation)
        }
    }

    private func recordCancellation(invocation: Int) {
        cancelledInvocations.insert(invocation)
        for waiter in cancellationWaiters.removeValue(forKey: invocation) ?? [] {
            waiter.resume()
        }
    }
}

private actor FileBootstrapLifecycleRecorder: BridgeProductMetadataLifecycleTraceRecording {
    enum ResumeDispatch: Equatable {
        case sourceReopen
        case updateWithoutReopen
    }

    private var fileBootstrapFinishedCount = 0
    private var fileBootstrapFinishedWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var fileProducerStartedCount = 0
    private var fileProducerStartedWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var resumeDispatch: ResumeDispatch?
    private var resumeDispatchWaiters: [CheckedContinuation<ResumeDispatch, Never>] = []

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) {
        guard event.subscriptionKind == .fileMetadata else { return }
        switch event.stage {
        case .bootstrapStarted:
            fileProducerStartedCount += 1
            let readyWaiters = fileProducerStartedWaiters.filter {
                $0.count <= fileProducerStartedCount
            }
            fileProducerStartedWaiters.removeAll {
                $0.count <= fileProducerStartedCount
            }
            for waiter in readyWaiters { waiter.continuation.resume() }
        case .bootstrapFinished:
            fileBootstrapFinishedCount += 1
            if fileBootstrapFinishedCount == 2, resumeDispatch == nil {
                settleResumeDispatch(.updateWithoutReopen)
            }
            let readyWaiters = fileBootstrapFinishedWaiters.filter {
                $0.count <= fileBootstrapFinishedCount
            }
            fileBootstrapFinishedWaiters.removeAll {
                $0.count <= fileBootstrapFinishedCount
            }
            for waiter in readyWaiters { waiter.continuation.resume() }
        case .producerCancelled, .producerFailed, .sourceAcceptedEnqueued, .subscriptionResetEnqueued,
            .windowEnqueued:
            break
        }
    }

    func record(_: BridgeProductReviewMetadataPublicationTraceEvent) {}

    func recordResumeBuilderStarted() {
        settleResumeDispatch(.sourceReopen)
    }

    func waitForFileProducerFinished(count: Int) async {
        guard fileBootstrapFinishedCount < count else { return }
        await withCheckedContinuation { continuation in
            fileBootstrapFinishedWaiters.append((count: count, continuation: continuation))
        }
    }

    func waitForFileProducerStarted(count: Int) async {
        guard fileProducerStartedCount < count else { return }
        await withCheckedContinuation { continuation in
            fileProducerStartedWaiters.append((count: count, continuation: continuation))
        }
    }

    func waitForResumeDispatch() async -> ResumeDispatch {
        if let resumeDispatch { return resumeDispatch }
        return await withCheckedContinuation { continuation in
            resumeDispatchWaiters.append(continuation)
        }
    }

    private func settleResumeDispatch(_ dispatch: ResumeDispatch) {
        guard resumeDispatch == nil else { return }
        resumeDispatch = dispatch
        let waiters = resumeDispatchWaiters
        resumeDispatchWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume(returning: dispatch) }
    }
}

private func fileBootstrapSubscriptionOpenRequest(
    fixture: ProductFileSourceFixture
) throws -> BridgeProductControlRequest {
    try bridgeProductLifecycleControlRequest([
        "kind": "subscription.open",
        "paneSessionId": "pane-session-1",
        "requestId": "request-file-bootstrap-open-2",
        "requestSequence": 2,
        "subscription": [
            "source": [
                "cwdScope": NSNull(),
                "freshness": "live",
                "includeStatuses": true,
                "repoId": fixture.repoId.uuidString,
                "rootPathToken": StableKey.fromPath(fixture.rootURL),
                "worktreeId": fixture.worktreeId.uuidString,
            ],
            "subscriptionKind": "file.metadata",
        ],
        "subscriptionId": "file-subscription-1",
        "wireVersion": BridgeProductWireContract.version,
        "workerDerivationEpoch": 1,
        "workerInstanceId": "worker-instance-1",
    ])
}

private func pullResumedFileTree(
    from pump: BridgeProductSchemeFramePump
) async throws -> ResumedFileTree {
    var resumedSource: BridgeProductFileSourceIdentity?
    var rows: [BridgeProductFileTreeRow] = []
    while true {
        let frame = try await pullMetadataFrame(from: pump)
        guard case .subscriptionData(let data) = frame,
            let event = data.data.fileMetadataEvent
        else { continue }
        switch event {
        case .sourceAccepted(let accepted):
            resumedSource = accepted.source
        case .treeWindow(let window):
            rows.append(contentsOf: window.rows)
            if window.finalWindow {
                return ResumedFileTree(
                    source: try #require(resumedSource),
                    finalWindow: window,
                    rows: rows
                )
            }
        case .descriptorReady, .invalidated, .statusPatch, .treeDelta:
            continue
        }
    }
}

private enum FileBootstrapSuspensionTestError: Error {
    case expectedSourceAcceptance
}
