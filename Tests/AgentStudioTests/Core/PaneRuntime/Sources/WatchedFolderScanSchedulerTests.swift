import Foundation
import Testing

@testable import AgentStudio

@Suite("Watched-folder scan scheduler")
struct WatchedFolderScanSchedulerTests {
    @Test("terminal-result custody bounds scanning until transfer")
    func terminalResultCustodyBoundsScanning() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 2)
        let first = try fixture.makeRequest(name: "first")
        let second = try fixture.makeRequest(name: "second")
        let third = try fixture.makeRequest(name: "third")

        _ = await fixture.scheduler.submit(first)
        _ = await fixture.scheduler.submit(second)
        _ = await fixture.scheduler.submit(third)
        let firstStart = await fixture.scanner.nextStart()
        let secondStart = await fixture.scanner.nextStart()
        await fixture.scanner.finish(firstStart, with: completeResult())
        await fixture.scanner.finish(secondStart, with: completeResult())

        #expect(await fixture.scanner.startedQuantumCount() == 2)
        try await fixture.waitForState(
            .active(
                WatchedFolderScanSchedulerActiveState(
                    ready: 1,
                    activeQuanta: 0,
                    awaitingValidations: 0,
                    pendingResults: 2,
                    leasedResults: 0,
                    runningAndDirty: 0,
                    resultCustodyHighWater: 2
                )
            )
        )

        let firstLease = try await fixture.nextLease()
        #expect(await fixture.transfer(firstLease) == .transferred)
        let thirdStart = await fixture.scanner.nextStart()
        #expect(thirdStart.request.sourceID == third.sourceID)
        await fixture.scanner.finish(thirdStart, with: completeResult())

        try await fixture.transferAllResults(expectedCount: 2)
        await fixture.scheduler.shutdown()
        #expect(await fixture.scheduler.stateSnapshot() == .shutDown)
    }

    @Test("suspension requeues the same logical generation and dirty follow-up waits for transfer")
    func suspensionPreservesGenerationAndDefersDirtyFollowUp() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let request = try fixture.makeRequest(name: "root", cause: .initialAdd)

        _ = await fixture.scheduler.submit(request)
        let firstQuantum = await fixture.scanner.nextStart()
        _ = await fixture.scheduler.submit(
            WatchedFolderScanRequest(canonicalRoot: request.canonicalRoot, cause: .callback)
        )
        await fixture.scanner.suspend(firstQuantum)
        let secondQuantum = await fixture.scanner.nextStart()
        #expect(secondQuantum.scanRunGeneration == firstQuantum.scanRunGeneration)
        await fixture.scanner.finish(secondQuantum, with: completeResult())

        let initialLease = try await fixture.nextLease()
        #expect(initialLease.result.scanRunGeneration == 1)
        #expect(initialLease.result.schedulingMetrics.quantumSelectionCount == 2)
        #expect(initialLease.result.schedulingMetrics.followUpEvidence == .dirtyFollowUpQueued)
        #expect(await fixture.scanner.startedQuantumCount() == 2)

        #expect(await fixture.transfer(initialLease) == .transferred)
        let followUp = await fixture.scanner.nextStart()
        #expect(followUp.scanRunGeneration == 2)
        await fixture.scanner.finish(followUp, with: completeResult())
        let followUpLease = try await fixture.nextLease()
        #expect(followUpLease.result.schedulingMetrics.followUpEvidence == .startedFromDirtyFollowUp)
        #expect(await fixture.transfer(followUpLease) == .transferred)
        await fixture.scheduler.shutdown()
    }

    @Test(
        "round-robin quantum selection serves every ready root without sleeps",
        arguments: [10, 100, 300]
    )
    func roundRobinQuantumSelection(rootCount: Int) async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let requests = try (0..<rootCount).map { index in
            try fixture.makeRequest(name: "root-\(index)")
        }
        for request in requests { _ = await fixture.scheduler.submit(request) }

        var selectedSourceIDs: Set<FilesystemSourceID> = []
        for _ in 0..<rootCount {
            let selection = await fixture.scanner.nextStart()
            selectedSourceIDs.insert(selection.request.sourceID)
            await fixture.scanner.suspend(selection)
        }

        #expect(selectedSourceIDs.count == rootCount)
        await fixture.scheduler.shutdown()
    }

    @Test(
        "ready selection performs fixed work independent of scheduled fleet size",
        arguments: [10, 100, 300]
    )
    func readySelectionWorkIsFleetSizeIndependent(rootCount: Int) async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let requests = try (0..<rootCount).map { index in
            try fixture.makeRequest(name: "inspection-root-\(index)")
        }
        _ = await fixture.scheduler.submit(requests[0])
        var active = await fixture.scanner.nextStart()
        for request in requests.dropFirst() { _ = await fixture.scheduler.submit(request) }

        let before = await fixture.scheduler.readySelectionInspection()
        for _ in 0..<4 {
            await fixture.scanner.suspend(active)
            active = await fixture.scanner.nextStart()
        }
        let after = await fixture.scheduler.readySelectionInspection()

        #expect(after.scheduledRootCount == rootCount)
        #expect(after.selectionCount - before.selectionCount == 4)
        #expect(after.workUnitCount - before.workUnitCount == 4)
        await fixture.scheduler.shutdown()
    }

    @Test("ordinary trigger cannot erase queued repair custody")
    func ordinaryTriggerPreservesQueuedRepairCustody() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let blocker = try fixture.makeRequest(name: "blocker")
        let repairRoot = try SchedulerFixture.makeRoot(name: "repair")
        let participant = makeRepairParticipant()
        let generation = RepairGeneration(
            id: RepairGenerationID(registration: repairRoot.registration, sequence: 7),
            watermark: .recoveryRevision(11),
            trigger: .continuityLoss,
            participants: [participant]
        )
        let repair = WatchedFolderScanRequest(
            canonicalRoot: repairRoot,
            cause: .repair(
                WatchedFolderRepairObligation(
                    generation: generation,
                    unresolved: NonEmptyWatchedFolderRepairObligations(
                        first: participant,
                        remaining: []
                    )
                )
            )
        )

        _ = await fixture.scheduler.submit(blocker)
        let blockerStart = await fixture.scanner.nextStart()
        _ = await fixture.scheduler.submit(repair)
        _ = await fixture.scheduler.submit(
            WatchedFolderScanRequest(canonicalRoot: repairRoot, cause: .callback)
        )
        await fixture.scanner.finish(blockerStart, with: completeResult())
        let blockerLease = try await fixture.nextLease()
        #expect(await fixture.transfer(blockerLease) == .transferred)

        let repairStart = await fixture.scanner.nextStart()
        #expect(repairStart.request.cause == repair.cause)
        await fixture.scanner.finish(repairStart, with: completeResult())
        let repairLease = try await fixture.nextLease()
        #expect(repairLease.result.request.cause == repair.cause)
        #expect(await fixture.transfer(repairLease) == .transferred)
        await fixture.scheduler.shutdown()
    }

    @Test("retry re-presents the identical final result")
    func retryRepresentsIdenticalFinalResult() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let request = try fixture.makeRequest(name: "retry")
        _ = await fixture.scheduler.submit(request)
        let start = await fixture.scanner.nextStart()
        await fixture.scanner.finish(start, with: completeResult())

        let firstLease = try await fixture.nextLease()
        #expect(await fixture.retry(firstLease) == .queuedForRetry)
        let secondLease = try await fixture.nextLease()
        #expect(secondLease.result == firstLease.result)
        #expect(secondLease.leaseID != firstLease.leaseID)
        #expect(await fixture.transfer(secondLease) == .transferred)
        await fixture.scheduler.shutdown()
    }

    @Test("cancelled result waiter releases exclusive consumer for rebind")
    func cancelledWaiterAllowsConsumerRebind() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        #expect(await fixture.scheduler.bindResultConsumer(fixture.consumer) == .bound)
        let waitTask = Task {
            await fixture.scheduler.nextResultLease(for: fixture.consumer)
        }
        waitTask.cancel()
        #expect(await waitTask.value == .cancelled)
        #expect(await fixture.scheduler.unbindResultConsumer(fixture.consumer) == .unbound)

        let replacement = WatchedFolderScanResultConsumerToken.make()
        #expect(await fixture.scheduler.bindResultConsumer(replacement) == .bound)
        await fixture.scheduler.shutdown()
        #expect(await fixture.scheduler.stateSnapshot() == .shutDown)
    }

    @Test("shutdown remains draining until pending result custody transfers")
    func shutdownDrainsPendingResultCustody() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let request = try fixture.makeRequest(name: "shutdown-custody")
        _ = await fixture.scheduler.submit(request)
        let start = await fixture.scanner.nextStart()
        await fixture.scanner.finish(start, with: completeResult())

        try await fixture.waitForState(
            .active(
                WatchedFolderScanSchedulerActiveState(
                    ready: 0,
                    activeQuanta: 0,
                    awaitingValidations: 0,
                    pendingResults: 1,
                    leasedResults: 0,
                    runningAndDirty: 0,
                    resultCustodyHighWater: 1
                )
            )
        )
        await fixture.scheduler.shutdown()
        #expect(
            await fixture.scheduler.stateSnapshot()
                == .shuttingDown(
                    WatchedFolderScanSchedulerCustodyState(
                        activeQuanta: 0,
                        awaitingValidations: 0,
                        pendingResults: 1,
                        leasedResults: 0
                    )
                )
        )
        let lease = try await fixture.nextLease()
        #expect(await fixture.transfer(lease) == .transferred)
        #expect(await fixture.scheduler.stateSnapshot() == .shutDown)
    }

    @Test("replacement registration drops stale session and starts exact current request")
    func replacementRegistrationRejectsStaleCompletion() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let original = try fixture.makeRequest(name: "root", registrationGeneration: 1)
        let replacement = try fixture.makeRequest(
            name: "root",
            sourceID: original.sourceID,
            registrationGeneration: 2
        )

        _ = await fixture.scheduler.submit(original)
        let staleStart = await fixture.scanner.nextStart()
        _ = await fixture.scheduler.submit(replacement)
        await fixture.scanner.finish(staleStart, with: completeResult())
        let replacementStart = await fixture.scanner.nextStart()
        #expect(replacementStart.request.canonicalRoot == replacement.canonicalRoot)
        await fixture.scanner.finish(replacementStart, with: completeResult())

        let lease = try await fixture.nextLease()
        #expect(lease.result.schedulingMetrics.staleRegistrationDropCount == 1)
        #expect(await fixture.transfer(lease) == .transferred)
        await fixture.scheduler.shutdown()
    }

    @Test("replacement discards a stale pending result before lease and progresses current work")
    func replacementDiscardsStalePendingResultBeforeLease() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let original = try fixture.makeRequest(name: "pending-root", registrationGeneration: 1)
        let replacement = try fixture.makeRequest(
            name: "pending-root",
            sourceID: original.sourceID,
            registrationGeneration: 2
        )
        _ = await fixture.scheduler.submit(original)
        let originalStart = await fixture.scanner.nextStart()
        await fixture.scanner.finish(originalStart, with: completeResult())
        try await fixture.waitForPendingResultCount(1)
        _ = await fixture.scheduler.submit(replacement)

        let leaseTask = Task { try await fixture.nextLease() }
        let replacementStart = await fixture.scanner.nextStart()
        #expect(replacementStart.request.canonicalRoot == replacement.canonicalRoot)
        await fixture.scanner.finish(replacementStart, with: completeResult())
        let currentLease = try await leaseTask.value

        #expect(currentLease.result.request.canonicalRoot == replacement.canonicalRoot)
        #expect(currentLease.result.schedulingMetrics.staleRegistrationDropCount == 1)
        #expect(await fixture.transfer(currentLease) == .transferred)
        await fixture.scheduler.shutdown()
    }

    @Test("replacement makes an outstanding result lease stale before transfer")
    func replacementMakesOutstandingLeaseStale() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let original = try fixture.makeRequest(name: "leased-root", registrationGeneration: 1)
        let replacement = try fixture.makeRequest(
            name: "leased-root",
            sourceID: original.sourceID,
            registrationGeneration: 2
        )
        _ = await fixture.scheduler.submit(original)
        let originalStart = await fixture.scanner.nextStart()
        await fixture.scanner.finish(originalStart, with: completeResult())
        let staleLease = try await fixture.nextLease()
        _ = await fixture.scheduler.submit(replacement)

        #expect(await fixture.transfer(staleLease) == .staleResultDiscarded)
        let replacementStart = await fixture.scanner.nextStart()
        #expect(replacementStart.request.canonicalRoot == replacement.canonicalRoot)
        await fixture.scanner.finish(replacementStart, with: completeResult())
        let currentLease = try await fixture.nextLease()
        #expect(currentLease.result.schedulingMetrics.staleRegistrationDropCount == 1)
        #expect(await fixture.transfer(currentLease) == .transferred)
        await fixture.scheduler.shutdown()
    }

    @Test("run generation exhaustion is typed and never wraps")
    func runGenerationExhaustionIsTyped() async throws {
        let root = try SchedulerFixture.makeRoot(name: "exhausted")
        let fixture = try SchedulerFixture(
            maximumConcurrentScans: 1,
            initialRunGenerations: [root.sourceID: UInt64.max]
        )
        let request = WatchedFolderScanRequest(canonicalRoot: root, cause: .manual)

        #expect(
            await fixture.scheduler.submit(request)
                == .rejected(.scanRunGenerationExhausted(request.sourceID))
        )
        #expect(await fixture.scanner.startedQuantumCount() == 0)
        await fixture.scheduler.shutdown()
    }

    @Test("queue wait accumulates separately across quantum selections")
    func queueWaitAndQuantumCountRemainSeparate() async throws {
        let fixture = try SchedulerFixture(maximumConcurrentScans: 1)
        let request = try fixture.makeRequest(name: "metrics")
        let blocker = try fixture.makeRequest(name: "blocker")
        _ = await fixture.scheduler.submit(request)
        let first = await fixture.scanner.nextStart()
        _ = await fixture.scheduler.submit(blocker)
        await fixture.scanner.suspend(first)
        let blockerStart = await fixture.scanner.nextStart()
        fixture.clock.advance(by: .milliseconds(5))
        await fixture.scanner.finish(blockerStart, with: completeResult())
        let blockerLease = try await fixture.nextLease()
        #expect(await fixture.transfer(blockerLease) == .transferred)
        let second = await fixture.scanner.nextStart()
        await fixture.scanner.finish(second, with: completeResult())

        let lease = try await fixture.nextLease()
        #expect(lease.result.schedulingMetrics.queueWaitDuration == .milliseconds(5))
        #expect(lease.result.schedulingMetrics.quantumSelectionCount == 2)
        #expect(await fixture.transfer(lease) == .transferred)
        await fixture.scheduler.shutdown()
    }
}

private final class SchedulerTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: Duration = .zero

    func now() -> Duration { lock.withLock { elapsed } }
    func advance(by duration: Duration) { lock.withLock { elapsed += duration } }
}

private actor ControlledWatchedFolderScanner {
    struct Start: Sendable {
        let request: WatchedFolderScanRequest
        let scanRunGeneration: UInt64
    }

    private struct ActiveQuantum {
        let start: Start
        let continuation: CheckedContinuation<RepoScannerQuantumOutcome, Never>
    }

    private var activeBySourceID: [FilesystemSourceID: ActiveQuantum] = [:]
    private var bufferedStarts: [Start] = []
    private var startWaiters: [CheckedContinuation<Start, Never>] = []
    private var totalStarted = 0
    private var totalCancelled = 0

    func makeSession(
        request: WatchedFolderScanRequest,
        scanRunGeneration: UInt64
    ) -> WatchedFolderScannerSessionPort {
        let sessionID = RepoScannerSessionID(rawValue: UUIDv7.generate())
        return WatchedFolderScannerSessionPort(
            id: sessionID,
            advanceOneQuantum: {
                await self.advance(
                    request: request,
                    scanRunGeneration: scanRunGeneration
                )
            },
            cancel: {
                Task { await self.cancel(sourceID: request.sourceID) }
                return .cancellationRequested
            },
            consumeValidationCompletion: { _ in
                .rejected(.sessionFinished)
            }
        )
    }

    func nextStart() async -> Start {
        if !bufferedStarts.isEmpty { return bufferedStarts.removeFirst() }
        return await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(_ start: Start, with result: RepoScannerResult) {
        complete(start, with: .finished(result))
    }

    func suspend(_ start: Start) {
        complete(
            start,
            with: .suspended(
                usage: RepoScannerQuantumUsage(
                    enumeratedItemCount: 1,
                    enumeratedPathByteCount: 1,
                    candidateValidationCount: 0,
                    failureCount: 0,
                    traversalServiceDuration: .milliseconds(1)
                )
            )
        )
    }

    func startedQuantumCount() -> Int { totalStarted }
    func cancelledQuantumCount() -> Int { totalCancelled }

    private func advance(
        request: WatchedFolderScanRequest,
        scanRunGeneration: UInt64
    ) async -> RepoScannerQuantumOutcome {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let start = Start(request: request, scanRunGeneration: scanRunGeneration)
                activeBySourceID[request.sourceID] = ActiveQuantum(
                    start: start,
                    continuation: continuation
                )
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

    private func complete(_ start: Start, with outcome: RepoScannerQuantumOutcome) {
        guard let active = activeBySourceID.removeValue(forKey: start.request.sourceID) else {
            Issue.record("expected an active controlled scanner quantum")
            return
        }
        active.continuation.resume(returning: outcome)
    }

    private func cancel(sourceID: FilesystemSourceID) {
        guard let active = activeBySourceID.removeValue(forKey: sourceID) else { return }
        totalCancelled += 1
        active.continuation.resume(returning: .finished(cancelledResult()))
    }
}

private struct SchedulerFixture {
    let scanner = ControlledWatchedFolderScanner()
    let clock = SchedulerTestClock()
    let consumer = WatchedFolderScanResultConsumerToken.make()
    let scheduler: WatchedFolderScanScheduler

    init(
        maximumConcurrentScans: Int,
        initialRunGenerations: [FilesystemSourceID: UInt64] = [:]
    ) throws {
        let scanner = self.scanner
        let clock = self.clock
        scheduler = try WatchedFolderScanScheduler(
            maximumConcurrentScans: maximumConcurrentScans,
            initialScanRunGenerations: initialRunGenerations,
            now: clock.now,
            validationExecutor: RepoScannerValidationExecutor(
                validationClient: SchedulerUnusedValidationClient()
            ),
            sessionFactory: { request, generation in
                await scanner.makeSession(request: request, scanRunGeneration: generation)
            }
        )
    }

    func makeRequest(
        name: String,
        sourceID: FilesystemSourceID? = nil,
        registrationGeneration: UInt64 = 1,
        cause: WatchedFolderScanCause = .manual
    ) throws -> WatchedFolderScanRequest {
        WatchedFolderScanRequest(
            canonicalRoot: try Self.makeRoot(
                name: name,
                sourceID: sourceID,
                registrationGeneration: registrationGeneration
            ),
            cause: cause
        )
    }

    static func makeRoot(
        name: String,
        sourceID: FilesystemSourceID? = nil,
        registrationGeneration: UInt64 = 1
    ) throws -> RegisteredRootDescriptor {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "scheduler-\(name)-\(UUIDv7.generate())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceID =
            sourceID
            ?? FilesystemSourceID(kind: .watchedParentMembership, rootID: UUIDv7.generate())
        return try FilesystemSourceConfiguration.registerRoot(
            from: .hostAuthorized(
                FilesystemHostAuthorizedRootInput(
                    registration: FSEventRegistrationToken(
                        sourceID: sourceID,
                        registrationGeneration: registrationGeneration,
                        rootGeneration: 1
                    ),
                    authorizedBoundary: root,
                    registeredRoot: root
                )
            )
        )
    }

    func nextLease() async throws -> WatchedFolderScanResultLease {
        _ = await scheduler.bindResultConsumer(consumer)
        guard case .leased(let lease) = await scheduler.nextResultLease(for: consumer) else {
            Issue.record("expected a leased scheduled scan result")
            throw SchedulerTestError.expectedLease
        }
        return lease
    }

    func transfer(
        _ lease: WatchedFolderScanResultLease
    ) async -> WatchedFolderScanResultLeaseResolutionResult {
        await scheduler.resolveResultLease(
            for: consumer,
            leaseID: lease.leaseID,
            resolution: .transferred
        )
    }

    func retry(
        _ lease: WatchedFolderScanResultLease
    ) async -> WatchedFolderScanResultLeaseResolutionResult {
        await scheduler.resolveResultLease(
            for: consumer,
            leaseID: lease.leaseID,
            resolution: .retry
        )
    }

    func transferAllResults(expectedCount: Int) async throws {
        for _ in 0..<expectedCount {
            let lease = try await nextLease()
            #expect(await transfer(lease) == .transferred)
        }
    }

    func waitForState(
        _ expectedState: WatchedFolderScanSchedulerStateSnapshot
    ) async throws {
        for _ in 0..<10_000 {
            if await scheduler.stateSnapshot() == expectedState { return }
            await Task.yield()
        }
        Issue.record(
            "scheduler did not reach expected state; current state: \(await scheduler.stateSnapshot())"
        )
        throw SchedulerTestError.expectedState
    }

    func waitForPendingResultCount(_ expectedCount: Int) async throws {
        for _ in 0..<10_000 {
            if case .active(let snapshot) = await scheduler.stateSnapshot(),
                snapshot.pendingResults == expectedCount
            {
                return
            }
            await Task.yield()
        }
        Issue.record("scheduler did not reach pending result count \(expectedCount)")
        throw SchedulerTestError.expectedState
    }
}

private struct SchedulerUnusedValidationClient: RepoDiscoveryReadClient {
    func validateDiscoveryCandidate(at candidateURL: URL) async -> GitRepositoryDiscoveryOutcome {
        .failure(.serviceFailed(detail: "unexpected scheduler validation request"))
    }
}

private func completeResult() -> RepoScannerResult {
    .completeAuthoritative(
        CompleteRepoScan(
            verifiedEntries: [],
            counts: emptyScannerCounts(),
            serviceMetrics: .zero
        )
    )
}

private func cancelledResult() -> RepoScannerResult {
    .cancelled(
        CancelledRepoScan(
            verifiedEntries: [],
            counts: emptyScannerCounts(),
            serviceMetrics: .zero
        )
    )
}

private func emptyScannerCounts() -> RepoScannerEvidenceCounts {
    RepoScannerEvidenceCounts(
        directoryVisitCount: 0,
        directoryTraversalFailureCount: 0,
        entryMetadataFailureCount: 0,
        gitCandidateCount: 0,
        validationSuccessCount: 0,
        validationAuthoritativeNegativeCount: 0,
        validationTimeoutCount: 0,
        validationCancellationCount: 0,
        validationFailureCount: 0,
        scannerServiceInvocationCount: 1
    )
}

private func makeRepairParticipant() -> FilesystemRepairParticipantToken {
    FilesystemRepairParticipantToken(
        kind: .scanScheduler,
        participantID: UUIDv7.generate(),
        participantGeneration: 1
    )
}

private enum SchedulerTestError: Error {
    case expectedLease
    case expectedState
}
