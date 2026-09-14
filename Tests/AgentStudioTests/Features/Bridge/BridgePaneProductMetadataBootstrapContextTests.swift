import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane product metadata bootstrap context ownership")
struct BridgePaneProductMetadataBootstrapContextTests {
    @Test("unperturbed real File bootstrap emits its final tree")
    func unperturbedRealFileBootstrapEmitsFinalTree() async throws {
        let result = try await runRealFileBootstrapScenario(induceReplayCommitOverlap: false)

        #expect(result.resetCount == 0)
        #expect(result.finalTreeSources == [result.currentSource])
    }

    @Test("replacement bootstrap cannot lose the current File final tree")
    func replacementBootstrapPreservesCurrentFileFinalTree() async throws {
        let result = try await runRealFileBootstrapScenario(induceReplayCommitOverlap: true)

        #expect(result.resetCount == 0)
        #expect(result.finalTreeSources == [result.currentSource])
    }
}

private struct BootstrapContextScenarioResult {
    let currentSource: BridgeProductFileSourceIdentity
    let finalTreeSources: [BridgeProductFileSourceIdentity]
    let resetCount: Int
}

private struct BootstrapContextScenarioResources {
    let coordinator: BridgePaneProductMetadataCoordinator
    let fixture: ProductFileSourceFixture
    let frameCollector: BootstrapContextMetadataFrameCollector
    let frameDrain: Task<Void, any Error>
    let harness: BridgeProductSessionLifecycleHarness
    let lifecycleRecorder: BootstrapContextLifecycleRecorder
    let producerLease: BridgeProductProducerLease
    let pump: BridgeProductSchemeFramePump
    let sourceObserver: BootstrapContextSourceAcceptedObserver
}

private struct BootstrapContextOpenedControl {
    let effect: BridgeProductSessionCompletionEffect
    let token: BridgeProductControlAdmissionToken
}

private func runRealFileBootstrapScenario(
    induceReplayCommitOverlap: Bool
) async throws -> BootstrapContextScenarioResult {
    let resources = try await makeBootstrapContextScenarioResources(
        induceReplayCommitOverlap: induceReplayCommitOverlap
    )
    defer { resources.fixture.remove() }
    var pendingControlToken: BridgeProductControlAdmissionToken?
    var didCancelSubscription = false

    do {
        await resources.coordinator.install(
            request: try bootstrapContextMetadataStreamRequest(),
            lease: resources.producerLease,
            productAdmission: resources.harness.productAdmission.context,
            session: resources.harness.session
        )
        let openedControl = try await commitBootstrapContextFileSubscription(
            resources: resources
        )
        pendingControlToken = openedControl.token
        await runBootstrapContextSchedule(
            resources: resources,
            openEffect: openedControl.effect,
            induceReplayCommitOverlap: induceReplayCommitOverlap
        )
        await resources.harness.session.settleControlProviderDispatch(token: openedControl.token)
        pendingControlToken = nil
        try await cancelBootstrapContextFileSubscription(
            harness: resources.harness,
            coordinator: resources.coordinator
        )
        didCancelSubscription = true
        await resources.frameCollector.waitUntilCurrentSubscriptionCancellation()
        let result = try await bootstrapContextScenarioResult(resources: resources)
        try await finishBootstrapContextScenario(resources)
        return result
    } catch {
        await cleanupFailedBootstrapContextScenario(
            resources: resources,
            pendingControlToken: pendingControlToken,
            didCancelSubscription: didCancelSubscription
        )
        throw error
    }
}

private func makeBootstrapContextScenarioResources(
    induceReplayCommitOverlap: Bool
) async throws -> BootstrapContextScenarioResources {
    let harness = try await BridgeProductSessionLifecycleHarness.opened()
    let fixture = try ProductFileSourceFixture(fileCount: 2, productAdmission: harness.productAdmission)
    do {
        let producerLease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: producerLease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let frameCollector = BootstrapContextMetadataFrameCollector()
        let lifecycleRecorder = BootstrapContextLifecycleRecorder(
            holdFirstBootstrapStart: induceReplayCommitOverlap
        )
        let sourceObserver = BootstrapContextSourceAcceptedObserver(
            holdFirstAcceptance: induceReplayCommitOverlap
        )
        let source = fixture.makeSource(sourceAcceptedObserver: { acceptedSource in
            await sourceObserver.record(acceptedSource)
        })
        let foregroundAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: foregroundAdmission.source,
            lifecycleTraceRecorder: lifecycleRecorder
        )
        let frameDrain = Task {
            try await drainBootstrapContextMetadataFrames(from: pump, into: frameCollector)
        }
        return .init(
            coordinator: coordinator,
            fixture: fixture,
            frameCollector: frameCollector,
            frameDrain: frameDrain,
            harness: harness,
            lifecycleRecorder: lifecycleRecorder,
            producerLease: producerLease,
            pump: pump,
            sourceObserver: sourceObserver
        )
    } catch {
        fixture.remove()
        throw error
    }
}

private func commitBootstrapContextFileSubscription(
    resources: BootstrapContextScenarioResources
) async throws -> BootstrapContextOpenedControl {
    let request = try bootstrapContextFileSubscriptionOpenRequest(fixture: resources.fixture)
    let token = try #require(
        bootstrapContextControlExecutionToken(try await resources.harness.begin(request))
    )
    #expect(await resources.harness.session.claimControlProviderDispatch(token: token))
    let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
        correlating: request,
        interestSha256:
            BridgeProductSubscriptionInterestState
            .fileMetadata(interests: [], pathScope: []).sha256Hex()
    )
    let effect = try await resources.harness.session.completeControl(
        token: token,
        exactResponseBytes: try JSONEncoder().encode(response)
    )
    return .init(effect: effect, token: token)
}

private func runBootstrapContextSchedule(
    resources: BootstrapContextScenarioResources,
    openEffect: BridgeProductSessionCompletionEffect,
    induceReplayCommitOverlap: Bool
) async {
    guard induceReplayCommitOverlap else {
        await resources.coordinator.apply(
            openEffect,
            productAdmission: resources.harness.productAdmission.context
        )
        await resources.lifecycleRecorder.waitUntilBootstrapFinished(count: 1)
        return
    }
    let replay = Task {
        await resources.coordinator.replaySubscriptionsForInstalledStream()
    }
    await resources.lifecycleRecorder.waitUntilFirstBootstrapStartIsHeld()
    await resources.coordinator.apply(
        openEffect,
        productAdmission: resources.harness.productAdmission.context
    )
    await resources.sourceObserver.waitUntilFirstAcceptanceIsHeld()
    await resources.lifecycleRecorder.releaseFirstBootstrapStart()
    await resources.lifecycleRecorder.waitUntilBootstrapFinished(count: 1)
    await resources.sourceObserver.releaseFirstAcceptance()
    await resources.lifecycleRecorder.waitUntilBootstrapFinished(count: 2)
    await replay.value
}

private func bootstrapContextScenarioResult(
    resources: BootstrapContextScenarioResources
) async throws -> BootstrapContextScenarioResult {
    let collectedFrames = await resources.frameCollector.frames
    let currentSource = try #require(await resources.sourceObserver.firstAcceptedSource)
    let finalTreeSources = collectedFrames.compactMap { frame -> BridgeProductFileSourceIdentity? in
        guard case .subscriptionData(let data) = frame,
            let event = data.data.fileMetadataEvent,
            case .treeWindow(let window) = event,
            window.finalWindow
        else { return nil }
        return window.source
    }
    let resetCount = collectedFrames.count { frame in
        guard case .subscriptionReset(let reset) = frame else { return false }
        return reset.identity.subscriptionIdentity.subscriptionId == "file-subscription-1"
    }
    return .init(
        currentSource: currentSource,
        finalTreeSources: finalTreeSources,
        resetCount: resetCount
    )
}

private func finishBootstrapContextScenario(
    _ resources: BootstrapContextScenarioResources
) async throws {
    await resources.coordinator.uninstall(lease: resources.producerLease)
    #expect(await resources.pump.cancel())
    try await resources.frameDrain.value
}

private func cleanupFailedBootstrapContextScenario(
    resources: BootstrapContextScenarioResources,
    pendingControlToken: BridgeProductControlAdmissionToken?,
    didCancelSubscription: Bool
) async {
    await resources.lifecycleRecorder.releaseFirstBootstrapStart()
    await resources.sourceObserver.releaseFirstAcceptance()
    if let pendingControlToken {
        await resources.harness.session.settleControlProviderDispatch(token: pendingControlToken)
    }
    if !didCancelSubscription {
        _ = try? await cancelBootstrapContextFileSubscription(
            harness: resources.harness,
            coordinator: resources.coordinator
        )
    }
    await resources.coordinator.uninstall(lease: resources.producerLease)
    _ = await resources.pump.cancel()
    _ = await resources.frameDrain.result
}

private actor BootstrapContextLifecycleRecorder: BridgeProductMetadataLifecycleTraceRecording {
    private var bootstrapFinishedCount = 0
    private var bootstrapFinishedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private let holdFirstBootstrapStart: Bool
    private var firstBootstrapStartHeld = false
    private var firstBootstrapStartHeldWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstBootstrapStartRelease: CheckedContinuation<Void, Never>?

    init(holdFirstBootstrapStart: Bool) {
        self.holdFirstBootstrapStart = holdFirstBootstrapStart
    }

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) async {
        if event.stage == .bootstrapStarted, holdFirstBootstrapStart, !firstBootstrapStartHeld {
            firstBootstrapStartHeld = true
            let waiters = firstBootstrapStartHeldWaiters
            firstBootstrapStartHeldWaiters.removeAll(keepingCapacity: false)
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                firstBootstrapStartRelease = continuation
            }
        }
        guard event.stage == .bootstrapFinished else { return }
        bootstrapFinishedCount += 1
        let readyWaiters = bootstrapFinishedWaiters.filter { bootstrapFinishedCount >= $0.0 }
        bootstrapFinishedWaiters.removeAll { bootstrapFinishedCount >= $0.0 }
        for (_, waiter) in readyWaiters { waiter.resume() }
    }

    func record(_: BridgeProductReviewMetadataPublicationTraceEvent) async {}

    func waitUntilFirstBootstrapStartIsHeld() async {
        guard !firstBootstrapStartHeld else { return }
        await withCheckedContinuation { continuation in
            firstBootstrapStartHeldWaiters.append(continuation)
        }
    }

    func releaseFirstBootstrapStart() {
        firstBootstrapStartRelease?.resume()
        firstBootstrapStartRelease = nil
    }

    func waitUntilBootstrapFinished(count: Int) async {
        guard bootstrapFinishedCount < count else { return }
        await withCheckedContinuation { continuation in
            bootstrapFinishedWaiters.append((count, continuation))
        }
    }
}

private actor BootstrapContextSourceAcceptedObserver {
    private(set) var acceptedSources: [BridgeProductFileSourceIdentity] = []
    private let holdFirstAcceptance: Bool
    private var firstAcceptanceHeldWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstAcceptanceRelease: CheckedContinuation<Void, Never>?

    init(holdFirstAcceptance: Bool) {
        self.holdFirstAcceptance = holdFirstAcceptance
    }

    var firstAcceptedSource: BridgeProductFileSourceIdentity? {
        acceptedSources.first
    }

    func record(_ source: BridgeProductFileSourceIdentity) async {
        acceptedSources.append(source)
        guard holdFirstAcceptance, acceptedSources.count == 1 else { return }
        let waiters = firstAcceptanceHeldWaiters
        firstAcceptanceHeldWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            firstAcceptanceRelease = continuation
        }
    }

    func waitUntilFirstAcceptanceIsHeld() async {
        guard !acceptedSources.isEmpty else {
            await withCheckedContinuation { continuation in
                firstAcceptanceHeldWaiters.append(continuation)
            }
            return
        }
    }

    func releaseFirstAcceptance() {
        firstAcceptanceRelease?.resume()
        firstAcceptanceRelease = nil
    }
}

private actor BootstrapContextMetadataFrameCollector {
    private(set) var frames: [BridgeProductMetadataFrame] = []
    private var cancellationObserved = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func append(_ frame: BridgeProductMetadataFrame) {
        frames.append(frame)
        guard case .subscriptionCancelled(let cancelled) = frame,
            cancelled.identity.subscriptionIdentity.subscriptionId == "file-subscription-1"
        else { return }
        cancellationObserved = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    func waitUntilCurrentSubscriptionCancellation() async {
        guard !cancellationObserved else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }
}

private func drainBootstrapContextMetadataFrames(
    from pump: BridgeProductSchemeFramePump,
    into collector: BootstrapContextMetadataFrameCollector
) async throws {
    while true {
        switch await pump.nextFrame() {
        case .frame(let delivery):
            let decoder = try BridgeProductMetadataFrameDecoder()
            let frame = try decoder.append(delivery.frame.data).first
            guard await pump.acknowledgeFrameConsumed(delivery.receipt) else {
                throw BootstrapContextTestError.frameAcknowledgementRejected
            }
            if let frame {
                await collector.append(frame)
            }
        case .cancelled, .finished:
            return
        case .rejected:
            throw BootstrapContextTestError.framePullRejected
        }
    }
}

private enum BootstrapContextTestError: Error {
    case frameAcknowledgementRejected
    case framePullRejected
}

private func bootstrapContextControlExecutionToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token, _) = admission else { return nil }
    return token
}

private func bootstrapContextFileSubscriptionOpenRequest(
    fixture: ProductFileSourceFixture
) throws -> BridgeProductControlRequest {
    try bridgeProductLifecycleControlRequest(
        bootstrapContextControlIdentity(
            kind: "subscription.open",
            requestId: "bootstrap-context-file-open",
            requestSequence: 2,
            workerDerivationEpoch: 0
        ).merging([
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
        ]) { _, new in new }
    )
}

private func bootstrapContextFileSubscriptionCancelRequest(
    requestSequence: Int
) throws -> BridgeProductControlRequest {
    try bridgeProductLifecycleControlRequest(
        bootstrapContextControlIdentity(
            kind: "subscription.cancel",
            requestId: "bootstrap-context-file-cancel",
            requestSequence: requestSequence,
            workerDerivationEpoch: 0
        ).merging([
            "subscriptionId": "file-subscription-1",
            "subscriptionKind": "file.metadata",
        ]) { _, new in new }
    )
}

private func bootstrapContextControlIdentity(
    kind: String,
    requestId: String,
    requestSequence: Int,
    workerDerivationEpoch: Int
) -> [String: Any] {
    [
        "kind": kind,
        "paneSessionId": "pane-session-1",
        "requestId": requestId,
        "requestSequence": requestSequence,
        "wireVersion": BridgeProductWireContract.version,
        "workerDerivationEpoch": workerDerivationEpoch,
        "workerInstanceId": "worker-instance-1",
    ]
}

private func bootstrapContextMetadataStreamRequest() throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": "metadata-stream-1",
            "paneSessionId": "pane-session-1",
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataStreamRequest.self, from: data)
}

private func cancelBootstrapContextFileSubscription(
    harness: BridgeProductSessionLifecycleHarness,
    coordinator: BridgePaneProductMetadataCoordinator
) async throws {
    let request = try bootstrapContextFileSubscriptionCancelRequest(requestSequence: 3)
    guard
        let token = bootstrapContextControlExecutionToken(
            try await harness.begin(request)
        )
    else { return }
    guard await harness.session.claimControlProviderDispatch(token: token) else { return }
    let response = try BridgeProductControlResponse.subscriptionCancelAccepted(correlating: request)
    let effect = try await harness.session.completeControl(
        token: token,
        exactResponseBytes: try JSONEncoder().encode(response)
    )
    await coordinator.apply(effect, productAdmission: harness.productAdmission.context)
    await harness.session.settleControlProviderDispatch(token: token)
}
