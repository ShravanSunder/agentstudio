import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemActor Watched Folders")
struct FilesystemActorWatchedFolderTests {
    @Test("binding result-drain state retains awaitable shutdown custody")
    func bindingResultDrainStateRetainsAwaitableShutdownCustody() async throws {
        let gate = ResultDrainTaskGate()
        let bindingTask = Task {
            await gate.pauseUntilReleased()
        }
        let state = FilesystemWatchedFolderResultDrainState.bindingConsumer(
            id: UUIDv7.generate(),
            task: bindingTask
        )

        await gate.waitUntilEntered()
        let shutdownCustodyTask = try #require(state.task)
        let completionProbe = ResultDrainTaskCompletionProbe()
        let shutdownWait = Task {
            await shutdownCustodyTask.value
            await completionProbe.recordCompletion()
        }

        await boundedYields()
        #expect(await completionProbe.isComplete == false)

        await gate.release()
        await shutdownWait.value
        #expect(await completionProbe.isComplete)
    }

    @Test("running result-drain state retains awaitable shutdown custody")
    func runningResultDrainStateRetainsAwaitableShutdownCustody() async throws {
        let gate = ResultDrainTaskGate()
        let runningTask = Task {
            await gate.pauseUntilReleased()
        }
        let state = FilesystemWatchedFolderResultDrainState.running(
            id: UUIDv7.generate(),
            task: runningTask
        )

        await gate.waitUntilEntered()
        let shutdownCustodyTask = try #require(state.task)
        let completionProbe = ResultDrainTaskCompletionProbe()
        let shutdownWait = Task {
            await shutdownCustodyTask.value
            await completionProbe.recordCompletion()
        }

        await boundedYields()
        #expect(await completionProbe.isComplete == false)

        await gate.release()
        await shutdownWait.value
        #expect(await completionProbe.isComplete)
    }

    @Test("manual refresh waits for the exact covered result")
    func manualRefreshWaitsForExactCoveredResult() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }

        let repoFromInitialDemand = fixture.watchedFolder.appending(path: "initial-repo")
        let repoFromManualDemand = fixture.watchedFolder.appending(path: "manual-repo")
        let initialRefresh = Task {
            await fixture.actor.refreshWatchedFolders([fixture.watchedPath])
        }
        let initialStart = await fixture.scanner.nextStart()
        let callbackRoutingID = try #require(fixture.fseventClient.registeredWorktreeIds.first)
        #expect(initialStart.request.cause == .initialAdd)
        #expect(initialStart.request.sourceID.rootID == fixture.watchedPath.id)
        #expect(initialStart.request.sourceID.kind == .watchedParentMembership)
        #expect(callbackRoutingID != fixture.watchedPath.id)
        await fixture.scanner.finish(initialStart, with: completeResult(entries: []))
        _ = await initialRefresh.value

        fixture.fseventClient.send(
            FSEventBatch(
                worktreeId: callbackRoutingID,
                paths: [fixture.watchedFolder.appending(path: "repo/.git/HEAD").path]
            )
        )
        let callbackStart = await fixture.scanner.nextStart()
        #expect(callbackStart.request.cause == .callback)

        let refresh = Task {
            await fixture.actor.refreshWatchedFolders([fixture.watchedPath])
        }
        await fixture.scanner.finish(
            callbackStart,
            with: completeResult(entries: [cloneEntry(repoFromInitialDemand)])
        )
        let exactManualStart = await fixture.scanner.nextStart()
        #expect(exactManualStart.request.cause == .manual)

        let completionProbe = RefreshCompletionProbe()
        let observedRefresh = Task {
            let summary = await refresh.value
            await completionProbe.record(summary)
        }
        await boundedYields()
        #expect(await completionProbe.summary() == nil)

        await fixture.scanner.finish(
            exactManualStart,
            with: completeResult(entries: [cloneEntry(repoFromManualDemand)])
        )
        await observedRefresh.value

        #expect(
            await completionProbe.summary()?.repoPaths(in: fixture.watchedFolder)
                == [canonicalURL(repoFromManualDemand)]
        )
        await fixture.actor.shutdown()
    }

    @Test("partial and cancelled results merge positives without removing prior inventory")
    func partialAndCancelledResultsAreAdditive() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }

        let clone = fixture.watchedFolder.appending(path: "app")
        let retainedClone = fixture.watchedFolder.appending(path: "retained")
        let linkedA = fixture.watchedFolder.appending(path: "app-a")
        let linkedB = fixture.watchedFolder.appending(path: "app-b")
        let linkedC = fixture.watchedFolder.appending(path: "app-c")
        _ = await fixture.performInitialRefresh(
            result: completeResult(entries: [
                cloneEntry(clone),
                linkedEntry(linkedA, parentClone: clone),
                cloneEntry(retainedClone),
            ])
        )

        let partialSummary = await fixture.performRefresh(
            result: partialResult(entries: [
                cloneEntry(clone),
                linkedEntry(linkedB, parentClone: clone),
            ])
        )
        #expect(
            Set(partialSummary.repoPaths(in: fixture.watchedFolder))
                == Set([canonicalURL(clone), canonicalURL(retainedClone)])
        )

        let cancelledSummary = await fixture.performRefresh(
            result: cancelledResult(entries: [
                cloneEntry(clone),
                linkedEntry(linkedC, parentClone: clone),
            ])
        )
        #expect(
            Set(cancelledSummary.repoPaths(in: fixture.watchedFolder))
                == Set([canonicalURL(clone), canonicalURL(retainedClone)])
        )

        let events = await fixture.topologyEvents()
        #expect(
            events.discovered.contains(
                RepoDiscoveryEvent(
                    repoPath: canonicalURL(clone),
                    linkedWorktrees: .scanned([
                        canonicalURL(linkedA),
                        canonicalURL(linkedB),
                        canonicalURL(linkedC),
                    ])
                )
            )
        )
        #expect(events.removed.isEmpty)
        await fixture.actor.shutdown()
    }

    @Test("concurrent manual refreshes serialize into distinct tracked scans")
    func concurrentManualRefreshesSerialize() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }
        _ = await fixture.performInitialRefresh(result: completeResult(entries: []))

        let firstRefresh = Task {
            await fixture.actor.refreshWatchedFolders([fixture.watchedPath])
        }
        let firstManualStart = await fixture.scanner.nextStart()
        #expect(firstManualStart.request.cause == .manual)

        let secondRefreshProbe = RefreshCompletionProbe()
        let secondRefresh = Task {
            let summary = await fixture.actor.refreshWatchedFolders([fixture.watchedPath])
            await secondRefreshProbe.record(summary)
        }
        await boundedYields()
        #expect(await fixture.scanner.startedQuantumCount() == 2)

        await fixture.scanner.finish(firstManualStart, with: completeResult(entries: []))
        _ = await firstRefresh.value
        let secondManualStart = await fixture.scanner.nextStart()
        #expect(secondManualStart.request.cause == .manual)
        #expect(await secondRefreshProbe.summary() == nil)

        await fixture.scanner.finish(secondManualStart, with: completeResult(entries: []))
        await secondRefresh.value
        #expect(await secondRefreshProbe.summary() != nil)
        await fixture.actor.shutdown()
    }

    @Test("exact complete result removes absent clones")
    func exactCompleteResultRemovesAbsentClones() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }

        let removedClone = fixture.watchedFolder.appending(path: "removed")
        let retainedClone = fixture.watchedFolder.appending(path: "retained")
        _ = await fixture.performInitialRefresh(
            result: completeResult(entries: [
                cloneEntry(removedClone),
                cloneEntry(retainedClone),
            ])
        )
        await fixture.resetTopologyEventRecording()

        let summary = await fixture.performRefresh(
            result: completeResult(entries: [cloneEntry(retainedClone)])
        )
        let events = await fixture.topologyEvents()

        #expect(summary.repoPaths(in: fixture.watchedFolder) == [canonicalURL(retainedClone)])
        #expect(events.discovered.isEmpty)
        #expect(events.removed == Set([canonicalURL(removedClone)]))
        await fixture.actor.shutdown()
    }

    @Test("shutdown resumes a manual refresh with a pending scan result")
    func shutdownResumesPendingManualRefresh() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }
        _ = await fixture.performInitialRefresh(result: completeResult(entries: []))

        let refresh = Task {
            await fixture.actor.refreshWatchedFolders([fixture.watchedPath])
        }
        let pendingManualStart = await fixture.scanner.nextStart()
        #expect(pendingManualStart.request.cause == .manual)

        await fixture.actor.shutdown()
        let summary = await refresh.value

        #expect(summary.repoPaths(in: fixture.watchedFolder).isEmpty)
    }

    @Test("unavailable and failed results preserve prior inventory")
    func unavailableAndFailedResultsPreservePriorInventory() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }

        let clone = fixture.watchedFolder.appending(path: "preserved")
        _ = await fixture.performInitialRefresh(
            result: completeResult(entries: [cloneEntry(clone)])
        )
        await fixture.resetTopologyEventRecording()

        let unavailableSummary = await fixture.performRefresh(result: unavailableResult())
        let failedSummary = await fixture.performRefresh(result: failedResult())
        let events = await fixture.topologyEvents()

        #expect(unavailableSummary.repoPaths(in: fixture.watchedFolder) == [canonicalURL(clone)])
        #expect(failedSummary.repoPaths(in: fixture.watchedFolder) == [canonicalURL(clone)])
        #expect(events.discovered.isEmpty)
        #expect(events.removed.isEmpty)
        await fixture.actor.shutdown()
    }

    @Test("only git topology callbacks submit a follow-up scan")
    func onlyGitTopologyCallbacksSubmitFollowUpScan() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }
        _ = await fixture.performInitialRefresh(result: completeResult(entries: []))

        let callbackRoutingID = try #require(fixture.fseventClient.registeredWorktreeIds.first)
        let scanCountBeforeCallbacks = await fixture.scanner.startedQuantumCount()
        fixture.fseventClient.send(
            FSEventBatch(
                worktreeId: callbackRoutingID,
                paths: [fixture.watchedFolder.appending(path: "repo/.gitignore").path]
            )
        )
        await boundedYields()
        #expect(await fixture.scanner.startedQuantumCount() == scanCountBeforeCallbacks)

        fixture.fseventClient.send(
            FSEventBatch(
                worktreeId: callbackRoutingID,
                paths: [fixture.watchedFolder.appending(path: "repo/.git/HEAD").path]
            )
        )
        let callbackStart = await fixture.scanner.nextStart()
        #expect(callbackStart.request.cause == .callback)
        #expect(callbackStart.request.sourceID.rootID == fixture.watchedPath.id)
        await fixture.scanner.finish(callbackStart, with: completeResult(entries: []))
        try await fixture.waitForStartedQuantumCount(scanCountBeforeCallbacks + 1)
        await fixture.actor.shutdown()
    }

    @Test("removing a watched path retires scheduler registration and callback routing")
    func removalRetiresSchedulerRegistrationAndCallbackRouting() async throws {
        let fixture = try await WatchedFolderActorFixture()
        defer { fixture.removeTemporaryRoot() }
        let clone = fixture.watchedFolder.appending(path: "removed-with-root")

        let initialRequest = await fixture.performInitialRefreshReturningRequest(
            result: completeResult(entries: [cloneEntry(clone)])
        )
        let callbackRoutingID = try #require(fixture.fseventClient.registeredWorktreeIds.first)
        await fixture.resetTopologyEventRecording()

        let summary = await fixture.actor.refreshWatchedFolders([])
        let events = await fixture.topologyEvents()
        let staleSubmission = await fixture.scheduler.submit(initialRequest)

        #expect(summary.repoPathsByWatchedFolder.isEmpty)
        #expect(fixture.fseventClient.unregisteredWorktreeIds == [callbackRoutingID])
        #expect(events.removed == Set([canonicalURL(clone)]))
        guard case .rejected(.staleRegistration) = staleSubmission else {
            Issue.record("retired watched-folder registration accepted a stale scan request")
            await fixture.actor.shutdown()
            return
        }
        await fixture.actor.shutdown()
    }
}

private actor ResultDrainTaskGate {
    private enum State {
        case awaitingEntry(entryWaiters: [CheckedContinuation<Void, Never>])
        case entered(releaseWaiters: [CheckedContinuation<Void, Never>])
        case released
    }

    private var state = State.awaitingEntry(entryWaiters: [])

    func pauseUntilReleased() async {
        let entryWaiters: [CheckedContinuation<Void, Never>]
        switch state {
        case .awaitingEntry(let retainedEntryWaiters):
            entryWaiters = retainedEntryWaiters
            state = .entered(releaseWaiters: [])
        case .entered, .released:
            preconditionFailure("result-drain task gate supports exactly one entry")
        }
        for entryWaiter in entryWaiters {
            entryWaiter.resume()
        }

        await withCheckedContinuation { continuation in
            switch state {
            case .awaitingEntry:
                preconditionFailure("result-drain task gate must enter before waiting for release")
            case .entered(var releaseWaiters):
                releaseWaiters.append(continuation)
                state = .entered(releaseWaiters: releaseWaiters)
            case .released:
                continuation.resume()
            }
        }
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            switch state {
            case .awaitingEntry(var entryWaiters):
                entryWaiters.append(continuation)
                state = .awaitingEntry(entryWaiters: entryWaiters)
            case .entered, .released:
                continuation.resume()
            }
        }
    }

    func release() {
        switch state {
        case .awaitingEntry:
            preconditionFailure("result-drain task gate cannot release before entry")
        case .entered(let releaseWaiters):
            state = .released
            for releaseWaiter in releaseWaiters {
                releaseWaiter.resume()
            }
        case .released:
            return
        }
    }
}

private actor ResultDrainTaskCompletionProbe {
    private enum State {
        case pending
        case complete
    }

    private var state = State.pending

    var isComplete: Bool {
        switch state {
        case .pending:
            false
        case .complete:
            true
        }
    }

    func recordCompletion() {
        state = .complete
    }
}

private actor ControlledActorWatchedFolderScanner {
    struct Start: Sendable {
        let request: WatchedFolderScanRequest
        let scanRunGeneration: UInt64
    }

    private struct ActiveQuantum {
        let continuation: CheckedContinuation<RepoScannerQuantumOutcome, Never>
    }

    private var activeBySourceID: [FilesystemSourceID: ActiveQuantum] = [:]
    private var bufferedStarts: [Start] = []
    private var startWaiters: [CheckedContinuation<Start, Never>] = []
    private var totalStarted = 0

    func makeSession(
        request: WatchedFolderScanRequest,
        scanRunGeneration: UInt64
    ) -> WatchedFolderScannerSessionPort {
        WatchedFolderScannerSessionPort(
            id: RepoScannerSessionID(rawValue: UUIDv7.generate()),
            advanceOneQuantum: {
                await self.advance(request: request, scanRunGeneration: scanRunGeneration)
            },
            cancel: {
                Task { await self.cancel(sourceID: request.sourceID) }
                return .cancellationRequested
            },
            consumeValidationCompletion: { _ in .rejected(.sessionFinished) }
        )
    }

    func nextStart() async -> Start {
        if !bufferedStarts.isEmpty { return bufferedStarts.removeFirst() }
        return await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(_ start: Start, with result: RepoScannerResult) {
        guard let active = activeBySourceID.removeValue(forKey: start.request.sourceID) else {
            Issue.record("expected an active watched-folder scanner quantum")
            return
        }
        active.continuation.resume(returning: .finished(result))
    }

    func startedQuantumCount() -> Int { totalStarted }

    private func advance(
        request: WatchedFolderScanRequest,
        scanRunGeneration: UInt64
    ) async -> RepoScannerQuantumOutcome {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let start = Start(request: request, scanRunGeneration: scanRunGeneration)
                activeBySourceID[request.sourceID] = ActiveQuantum(continuation: continuation)
                totalStarted += 1
                if startWaiters.isEmpty {
                    bufferedStarts.append(start)
                } else {
                    startWaiters.removeFirst().resume(returning: start)
                }
            }
        } onCancel: {
            Task { await self.cancel(sourceID: request.sourceID) }
        }
    }

    private func cancel(sourceID: FilesystemSourceID) {
        guard let active = activeBySourceID.removeValue(forKey: sourceID) else { return }
        active.continuation.resume(returning: .finished(cancelledResult(entries: [])))
    }
}

private struct WatchedFolderActorFixture {
    let scanner = ControlledActorWatchedFolderScanner()
    let bus = EventBus<RuntimeEnvelope>()
    let fseventClient = ControllableFSEventStreamClient()
    let watchedFolder: URL
    let watchedPath: WatchedPath
    let scheduler: WatchedFolderScanScheduler
    let actor: FilesystemActor

    private let eventRecorder: TopologyEventRecorder
    private let eventCollectionTask: Task<Void, Never>

    init() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "filesystem-actor-watched-folder-\(UUIDv7.generate())")
        let watchedFolder = URL(fileURLWithPath: temporaryRoot.path)
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        let watchedPath = WatchedPath(path: watchedFolder)
        let scanner = self.scanner
        let scheduler = try WatchedFolderScanScheduler(
            maximumConcurrentScans: 1,
            now: { .zero },
            validationExecutor: RepoScannerValidationExecutor(
                validationClient: ActorUnusedValidationClient()
            ),
            sessionFactory: { request, generation in
                await scanner.makeSession(request: request, scanRunGeneration: generation)
            }
        )
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fseventClient,
            watchedFolderScanScheduler: scheduler,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )
        let eventRecorder = TopologyEventRecorder()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)

        self.watchedFolder = watchedFolder
        self.watchedPath = watchedPath
        self.scheduler = scheduler
        self.actor = actor
        self.eventRecorder = eventRecorder
        eventCollectionTask = Task {
            for await envelope in stream {
                await eventRecorder.record(envelope)
            }
        }
    }

    func performInitialRefresh(result: RepoScannerResult) async -> WatchedFolderRefreshSummary {
        let (_, summary) = await runInitialRefresh(result: result)
        return summary
    }

    func performInitialRefreshReturningRequest(
        result: RepoScannerResult
    ) async -> WatchedFolderScanRequest {
        let (request, _) = await runInitialRefresh(result: result)
        return request
    }

    private func runInitialRefresh(
        result: RepoScannerResult
    ) async -> (WatchedFolderScanRequest, WatchedFolderRefreshSummary) {
        let refresh = Task { await actor.refreshWatchedFolders([watchedPath]) }
        let initialStart = await scanner.nextStart()
        await scanner.finish(initialStart, with: result)
        return (initialStart.request, await refresh.value)
    }

    func performRefresh(result: RepoScannerResult) async -> WatchedFolderRefreshSummary {
        let refresh = Task { await actor.refreshWatchedFolders([watchedPath]) }
        let start = await scanner.nextStart()
        await scanner.finish(start, with: result)
        return await refresh.value
    }

    func resetTopologyEventRecording() async {
        await boundedYields()
        await eventRecorder.reset()
    }

    func topologyEvents() async -> TopologyEventSet {
        await boundedYields()
        return await eventRecorder.snapshot()
    }

    func waitForStartedQuantumCount(_ expectedCount: Int) async throws {
        for _ in 0..<10_000 {
            if await scanner.startedQuantumCount() == expectedCount { return }
            await Task.yield()
        }
        Issue.record("scanner did not reach expected quantum count \(expectedCount)")
        throw WatchedFolderActorTestError.expectedScannerProgress
    }

    func removeTemporaryRoot() {
        eventCollectionTask.cancel()
        try? FileManager.default.removeItem(at: watchedFolder)
    }
}

private actor RefreshCompletionProbe {
    private var recordedSummary: WatchedFolderRefreshSummary?

    func record(_ summary: WatchedFolderRefreshSummary) {
        recordedSummary = summary
    }

    func summary() -> WatchedFolderRefreshSummary? { recordedSummary }
}

private struct RepoDiscoveryEvent: Equatable {
    let repoPath: URL
    let linkedWorktrees: LinkedWorktreeInfo
}

private struct TopologyEventSet: Equatable {
    var discovered: [RepoDiscoveryEvent] = []
    var removed: Set<URL> = []
}

private actor TopologyEventRecorder {
    private var events = TopologyEventSet()

    func record(_ envelope: RuntimeEnvelope) {
        guard case .system(let systemEnvelope) = envelope,
            case .topology(let topologyEvent) = systemEnvelope.event
        else { return }
        switch topologyEvent {
        case .repoDiscovered(let repoPath, _, let linkedWorktrees):
            events.discovered.append(
                RepoDiscoveryEvent(
                    repoPath: repoPath.standardizedFileURL,
                    linkedWorktrees: linkedWorktrees
                )
            )
        case .reposDiscovered(_, let repositories):
            events.discovered.append(
                contentsOf: repositories.map {
                    RepoDiscoveryEvent(
                        repoPath: $0.repoPath.standardizedFileURL,
                        linkedWorktrees: $0.linkedWorktrees
                    )
                }
            )
        case .repoRemoved(let repoPath):
            events.removed.insert(repoPath.standardizedFileURL)
        case .worktreeRegistered, .worktreeUnregistered:
            break
        }
    }

    func reset() { events = TopologyEventSet() }
    func snapshot() -> TopologyEventSet { events }
}

private struct ActorUnusedValidationClient: RepoDiscoveryReadClient {
    func validateDiscoveryCandidate(at candidateURL: URL) async -> GitRepositoryDiscoveryOutcome {
        .failure(.serviceFailed(detail: "unexpected actor test validation request"))
    }
}

private func cloneEntry(_ path: URL) -> RepoScanner.ResolvedGitEntry {
    RepoScanner.ResolvedGitEntry(
        path: path,
        kind: .cloneRoot,
        repositoryKey: path.standardizedFileURL.path
    )
}

private func canonicalURL(_ path: URL) -> URL {
    RepoScanner.canonicalURL(path)
}

private func linkedEntry(
    _ path: URL,
    parentClone: URL
) -> RepoScanner.ResolvedGitEntry {
    RepoScanner.ResolvedGitEntry(
        path: path,
        kind: .linkedWorktree(parentClonePath: parentClone),
        repositoryKey: parentClone.standardizedFileURL.path
    )
}

private func completeResult(entries: [RepoScanner.ResolvedGitEntry]) -> RepoScannerResult {
    .completeAuthoritative(
        CompleteRepoScan(
            verifiedEntries: entries,
            counts: scannerCounts(successCount: entries.count),
            serviceMetrics: .zero
        )
    )
}

private func partialResult(entries: [RepoScanner.ResolvedGitEntry]) -> RepoScannerResult {
    .partial(
        PartialRepoScan(
            verifiedEntries: entries,
            failures: NonEmptyScanFailures(
                first: .scannerServiceFailed(detail: "controlled partial result"),
                remaining: []
            ),
            counts: scannerCounts(successCount: entries.count, failureCount: 1),
            serviceMetrics: .zero
        )
    )
}

private func cancelledResult(entries: [RepoScanner.ResolvedGitEntry]) -> RepoScannerResult {
    .cancelled(
        CancelledRepoScan(
            verifiedEntries: entries,
            counts: scannerCounts(successCount: entries.count),
            serviceMetrics: .zero
        )
    )
}

private func unavailableResult() -> RepoScannerResult {
    .unavailable(
        UnavailableRepoScan(
            reason: .rootTraversalUnavailable(detail: "controlled unavailable result"),
            counts: scannerCounts(),
            serviceMetrics: .zero
        )
    )
}

private func failedResult() -> RepoScannerResult {
    .failed(
        FailedRepoScan(
            reason: .scannerServiceFailed(detail: "controlled failed result"),
            counts: scannerCounts(failureCount: 1),
            serviceMetrics: .zero
        )
    )
}

private func scannerCounts(
    successCount: Int = 0,
    failureCount: Int = 0
) -> RepoScannerEvidenceCounts {
    RepoScannerEvidenceCounts(
        directoryVisitCount: 0,
        directoryTraversalFailureCount: 0,
        entryMetadataFailureCount: 0,
        gitCandidateCount: successCount,
        validationSuccessCount: successCount,
        validationAuthoritativeNegativeCount: 0,
        validationTimeoutCount: 0,
        validationCancellationCount: 0,
        validationFailureCount: failureCount,
        scannerServiceInvocationCount: 1
    )
}

private func boundedYields() async {
    for _ in 0..<200 {
        await Task.yield()
    }
}

private enum WatchedFolderActorTestError: Error {
    case expectedScannerProgress
}
