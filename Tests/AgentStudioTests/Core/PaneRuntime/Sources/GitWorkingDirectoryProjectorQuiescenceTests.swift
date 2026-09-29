import AgentStudioGit
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("GitWorkingDirectoryProjector quiescence")
struct GitWorkingDirectoryProjectorQuiescenceTests {
    @Test("before start, shutdown, and restart have distinct subscription lifetimes")
    func lifecycleAndIgnoredEnvelope() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let source = LocalFactSource(vocabulary: FactVocabulary<GitProjectorScope, GitProjectorFact>.gitProjector)
        let facts = try source.attach()
        let projector = makeProjector(bus: bus, factSink: source.sink)

        await projector.start()
        let duplicateLabel = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "GitWorkingDirectoryProjector"
        )
        _ = await bus.post(ignoredTopologyEnvelope(seq: 1))
        try await facts.expectNext(in: .lifetime(1), .envelopeHandled(seq: 1, disposition: .ignored))
        #expect(duplicateLabel.deliveryCheckpoint().enqueuedCount == 1)

        await projector.shutdown()
        try await facts.expectNext(in: .lifetime(1), .shutdownCompleted)
        await projector.start()
        _ = await bus.post(ignoredTopologyEnvelope(seq: 2))
        try await facts.expectNext(in: .lifetime(2), .envelopeHandled(seq: 2, disposition: .ignored))
        await projector.shutdown()
        try await facts.expectNext(in: .lifetime(2), .shutdownCompleted)
        try await facts.finish()
    }

    @Test("a queued newest-buffer replacement reports loss after intake catches up")
    func queuedEnvelopeReportsLoss() async throws {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(capacityPerSource: 4, sourceKey: { $0.source.description })
        )
        let source = LocalFactSource(vocabulary: FactVocabulary<GitProjectorScope, GitProjectorFact>.gitProjector)
        let facts = try source.attach()
        let projector = makeProjector(bus: bus, subscriptionBufferLimit: 1, factSink: source.sink)
        _ = await bus.post(contentsOf: (1...4).map { ignoredTopologyEnvelope(seq: UInt64($0)) })
        await projector.start()

        try await facts.expectNext(in: .lifetime(1), .envelopesDropped(count: 3))
        try await facts.expectNext(in: .lifetime(1), .envelopeHandled(seq: 4, disposition: .ignored))
        await projector.shutdown()
        try await facts.expectNext(in: .lifetime(1), .shutdownCompleted)
        try await facts.finish()
    }

    @Test("coalesced provider work and a later waiter settle after the provider exits")
    func coalescedProviderAndConcurrentWaiters() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let providerStep = HeldStep<Void>("coalesced status provider")
        let provider = StubGitWorkingTreeStatusProvider { _ in
            try? await providerStep.arrive(())
            return cleanStatus()
        }
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .milliseconds(20),
            sleepClock: clock
        )
        await projector.start()
        let worktreeID = UUIDv7.generate()
        await projector.setActivity(worktreeId: worktreeID, isActiveInApp: true)
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: worktreeID))
        await clock.waitForPendingSleepCount()
        let firstWaiter = Task { await projector.waitUntilIdle() }

        clock.advance(by: .milliseconds(20))
        _ = try await providerStep.firstArrival()
        _ = await bus.post(ignoredTopologyEnvelope(seq: 2))
        let secondWaiter = Task { await projector.waitUntilIdle() }
        providerStep.release()

        #expect(await firstWaiter.value == .idle(droppedEnvelopes: 0))
        #expect(await secondWaiter.value == .idle(droppedEnvelopes: 0))
        await projector.shutdown()
    }

    @Test("cancelled retired provider remains outstanding until it actually exits")
    func retiredProviderLifetime() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let providerStep = HeldStep<Void>("retired provider", cancellation: .holdThroughCancellation)
        let provider = StubGitWorkingTreeStatusProvider { _ in
            try? await providerStep.arrive(())
            return cleanStatus()
        }
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )
        await projector.start()
        let worktreeID = UUIDv7.generate()
        await projector.setActivity(worktreeId: worktreeID, isActiveInApp: true)
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: worktreeID))
        _ = try await providerStep.firstArrival()

        _ = await bus.post(unregisteredEnvelope(seq: 2, worktreeID: worktreeID))
        try await providerStep.cancellationObserved()
        let idleTask = Task { await projector.waitUntilIdle() }
        providerStep.release()
        #expect(await idleTask.value == .idle(droppedEnvelopes: 0))
        await projector.shutdown()
    }

    @Test("cancelled waiters and shutdown each resume once")
    func cancellationAndShutdown() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let providerStep = HeldStep<Void>("shutdown provider", cancellation: .holdThroughCancellation)
        let provider = StubGitWorkingTreeStatusProvider { _ in
            try? await providerStep.arrive(())
            return cleanStatus()
        }
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )
        await projector.start()
        let worktreeID = UUIDv7.generate()
        await projector.setActivity(worktreeId: worktreeID, isActiveInApp: true)
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: worktreeID))
        _ = try await providerStep.firstArrival()

        let cancelledBeforeEntry = Task { () -> GitProjectorIdleOutcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return await projector.waitUntilIdle()
        }
        #expect(await cancelledBeforeEntry.value == .cancelled)
        let cancelledWhileWaiting = Task { await projector.waitUntilIdle() }
        let shutdownWaiter = Task { await projector.waitUntilIdle() }
        cancelledWhileWaiting.cancel()
        #expect(await cancelledWhileWaiting.value == .cancelled)
        let shutdownTask = Task { await projector.shutdown() }
        #expect(await shutdownWaiter.value == .shutdown)
        try await providerStep.cancellationObserved()
        providerStep.release()
        await shutdownTask.value
        #expect(await projector.waitUntilIdle() == .shutdown)
    }

    @Test("status failure debt remains outstanding until controlled backoff retries it")
    func statusBackoffDebt() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let attempts = StatusAttemptSequence(firstFailure: .providerReturnedNil)
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider(resultHandler: { _ in
                await attempts.nextResult()
            }),
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: .init(statusFailureBackoffBaseDelay: .milliseconds(10))
        )
        await projector.start()
        let worktreeID = UUIDv7.generate()
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: worktreeID))
        await clock.waitForPendingSleepCount()
        #expect(await projector.deferredStatusBackoffChangesetByWorktreeId[worktreeID] != nil)

        let idleTask = Task { await projector.waitUntilIdle() }
        clock.advance(by: .milliseconds(10))
        #expect(await idleTask.value == .idle(droppedEnvelopes: 0))
        #expect(await attempts.callCount == 2)
        await projector.shutdown()
    }

    @Test("capacity retry debt remains outstanding until controlled fallback retries it")
    func capacityRetryDebt() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let attempts = StatusAttemptSequence(firstFailure: .readCapacityExceeded)
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider(resultHandler: { _ in
                await attempts.nextResult()
            }),
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: .init(
                capacityRetryBaseDelay: .milliseconds(10),
                capacityRetryJitterMaxDelay: .zero
            )
        )
        await projector.start()
        let worktreeID = UUIDv7.generate()
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: worktreeID))
        await clock.waitForPendingSleepCount()
        #expect(await projector.capacityRetryWorktreeIds.contains(worktreeID))

        let idleTask = Task { await projector.waitUntilIdle() }
        clock.advance(by: .milliseconds(10))
        #expect(await idleTask.value == .idle(droppedEnvelopes: 0))
        #expect(await attempts.callCount == 2)
        await projector.shutdown()
    }

    @Test("admission pacing keeps the second accepted worktree pending")
    func admissionPacedDebt() async {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let attempts = StatusAttemptSequence(firstFailure: nil)
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider(resultHandler: { _ in
                await attempts.nextResult()
            }),
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: .init(
                backgroundStripeCount: 1,
                maxConcurrentStatusComputes: 1,
                minimumAutomaticStartInterval: .milliseconds(10)
            )
        )
        await projector.start()
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: UUIDv7.generate()))
        #expect(await projector.waitUntilIdle() == .idle(droppedEnvelopes: 0))
        #expect(await attempts.callCount == 1)

        let secondWorktreeID = UUIDv7.generate()
        _ = await bus.post(filesChangedEnvelope(seq: 2, worktreeID: secondWorktreeID))
        await clock.waitForPendingSleepCount()
        #expect(await projector.pendingByWorktreeId[secondWorktreeID] != nil)
        let idleTask = Task { await projector.waitUntilIdle() }
        clock.advance(by: .milliseconds(10))
        #expect(await idleTask.value == .idle(droppedEnvelopes: 0))
        #expect(await attempts.callCount == 2)
        await projector.shutdown()
    }

    @Test("a due periodic deadline stays active through exact-clean renewal")
    func activeDeadlineRenewal() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let renewalStep = HeldStep<Void>("exact-clean deadline renewal")
        let authority = GitCleanContinuityAuthority(
            registrationId: UUIDv7.generate(),
            observationIdentity: GitStatusObservationIdentity(rawValue: "quiescence-renewal"),
            registrationGeneration: 1,
            mutationEpoch: 0,
            uncertaintyEpoch: 0
        )
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: HeldExactCleanRenewalProvider(
                authority: authority,
                renewalStep: renewalStep
            ),
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: .init(activePaneCadence: .milliseconds(10))
        )
        await projector.start()
        let worktreeID = UUIDv7.generate()
        await projector.setActivity(worktreeId: worktreeID, isActiveInApp: true)
        _ = await bus.post(registeredEnvelope(seq: 1, worktreeID: worktreeID))
        #expect(await projector.waitUntilIdle() == .idle(droppedEnvelopes: 0))
        await clock.waitForPendingSleepCount()

        #expect(clock.advanceToNextPendingSleep())
        _ = try await renewalStep.firstArrival()
        let idleTask = Task { await projector.waitUntilIdle() }
        renewalStep.release()
        #expect(await idleTask.value == .idle(droppedEnvelopes: 0))
        await projector.shutdown()
    }

    @Test("work posted during a provider completion extends the same idle await")
    func followupWorkExtendsWait() async {
        let bus = EventBus<RuntimeEnvelope>()
        let attempts = StatusAttemptSequence(firstFailure: nil)
        let worktreeID = UUIDv7.generate()
        let provider = StubGitWorkingTreeStatusProvider(resultHandler: { _ in
            let result = await attempts.nextResult()
            if await attempts.callCount == 1 {
                _ = await bus.post(filesChangedEnvelope(seq: 2, worktreeID: worktreeID))
            }
            return result
        })
        let projector = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )
        await projector.start()
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: worktreeID))

        #expect(await projector.waitUntilIdle() == .idle(droppedEnvelopes: 0))
        #expect(await attempts.callCount == 2)
        await projector.shutdown()
    }

    @Test("collector catch-up waits for output application after projector idle")
    func collectorAppliesOutputBeforeNegativeAssertion() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let applyStep = HeldStep<Void>("collector snapshot application")
        let collector = ObservedGitEvents()
        await collector.start(on: bus, snapshotApplication: applyStep)
        let projector = makeProjector(bus: bus)
        await projector.start()
        _ = await bus.post(filesChangedEnvelope(seq: 1, worktreeID: UUIDv7.generate()))

        #expect(await projector.waitUntilIdle() == .idle(droppedEnvelopes: 0))
        _ = try await applyStep.firstArrival()
        let caughtUpTask = Task {
            let outcome = await collector.waitUntilCaughtUp()
            return (outcome, await collector.snapshotCount)
        }
        applyStep.release()
        let (outcome, snapshotCount) = await caughtUpTask.value
        #expect(outcome == .caughtUp(droppedEnvelopes: 0))
        #expect(snapshotCount == 1)

        await projector.shutdown()
        await collector.shutdown()
    }

    private func makeProjector(
        bus: EventBus<RuntimeEnvelope>,
        subscriptionBufferLimit: Int = 256,
        factSink: GitProjectorFactSink? = nil
    ) -> GitWorkingDirectoryProjector {
        GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in cleanStatus() },
            coalescingWindow: .zero,
            subscriptionBufferLimit: subscriptionBufferLimit,
            factSink: factSink
        )
    }

    private func ignoredTopologyEnvelope(seq: UInt64) -> RuntimeEnvelope {
        .system(
            SystemEnvelope.test(
                event: .topology(
                    .worktreeUnregistered(worktreeId: UUIDv7.generate(), repoId: UUIDv7.generate())
                ),
                source: .builtin(.gitWorkingDirectoryProjector),
                seq: seq
            )
        )
    }

    private func unregisteredEnvelope(seq: UInt64, worktreeID: UUID) -> RuntimeEnvelope {
        .system(
            SystemEnvelope.test(
                event: .topology(.worktreeUnregistered(worktreeId: worktreeID, repoId: worktreeID)),
                source: .builtin(.filesystemWatcher),
                seq: seq
            )
        )
    }

    private func registeredEnvelope(seq: UInt64, worktreeID: UUID) -> RuntimeEnvelope {
        .system(
            SystemEnvelope.test(
                event: .topology(
                    .worktreeRegistered(
                        worktreeId: worktreeID,
                        repoId: worktreeID,
                        rootPath: URL(fileURLWithPath: "/tmp/projector-quiescence-\(worktreeID.uuidString)")
                    )
                ),
                source: .builtin(.filesystemWatcher),
                seq: seq
            )
        )
    }

    private func filesChangedEnvelope(seq: UInt64, worktreeID: UUID) -> RuntimeEnvelope {
        let rootPath = URL(fileURLWithPath: "/tmp/projector-quiescence-\(worktreeID.uuidString)")
        return .worktree(
            WorktreeEnvelope.test(
                event: .filesystem(
                    .filesChanged(
                        changeset: FileChangeset(
                            worktreeId: worktreeID,
                            repoId: worktreeID,
                            rootPath: rootPath,
                            paths: ["file.txt"],
                            timestamp: ContinuousClock().now,
                            batchSeq: seq
                        )
                    )
                ),
                repoId: worktreeID,
                worktreeId: worktreeID,
                source: .system(.builtin(.filesystemWatcher)),
                seq: seq
            )
        )
    }
}

private func cleanStatus() -> GitWorkingTreeStatus {
    GitWorkingTreeStatus(
        summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
        branch: "main",
        origin: nil
    )
}

private actor StatusAttemptSequence {
    let firstFailure: GitWorkingTreeStatusUnavailableReason?
    private(set) var callCount = 0

    init(firstFailure: GitWorkingTreeStatusUnavailableReason?) {
        self.firstFailure = firstFailure
    }

    func nextResult() -> GitWorkingTreeStatusResult {
        callCount += 1
        if callCount == 1, let firstFailure {
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: firstFailure))
        }
        return .available(cleanStatus())
    }
}

private struct HeldExactCleanRenewalProvider: GitExactCleanStatusProviding {
    let authority: GitCleanContinuityAuthority
    let renewalStep: HeldStep<Void>

    func statusResult(for _: URL, pathspecs _: [String]?) async -> GitWorkingTreeStatusResult {
        .available(cleanStatus())
    }

    func exactCleanStatusFactsResult(for _: UUID, rootPath _: URL) async -> GitExactCleanStatusFactsResult {
        .available(GitWorkingTreeStatusFacts(status: cleanStatus(), exactCleanAuthority: authority))
    }

    func renewExactCleanAuthority(_: GitCleanContinuityAuthority) async -> GitExactCleanRenewalResult {
        try? await renewalStep.arrive(())
        return .renewed(authority)
    }

    func retireExactCleanAuthority(worktreeId _: UUID, rootPath _: URL) {}
}

private enum CollectorCatchupOutcome: Equatable, Sendable {
    case caughtUp(droppedEnvelopes: UInt64)
    case shutdown
    case cancelled
}

private actor ObservedGitEvents {
    private struct Waiter {
        let target: EventBusDeliveryCheckpoint
        let continuation: CheckedContinuation<CollectorCatchupOutcome, Never>
    }

    private var subscriptionHandle: EventBusSubscription<RuntimeEnvelope>?
    private var collectionTask: Task<Void, Never>?
    private var handledEnvelopeCount: UInt64 = 0
    private var waiters: [UUID: Waiter] = [:]
    private(set) var snapshotCount = 0

    func start(on bus: EventBus<RuntimeEnvelope>, snapshotApplication: HeldStep<Void>) async {
        let subscription = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "ObservedGitEvents"
        )
        subscriptionHandle = subscription
        collectionTask = Task { [weak self] in
            for await envelope in subscription {
                guard let self else { return }
                await self.record(envelope, snapshotApplication: snapshotApplication)
            }
            await self?.streamDidEnd()
        }
    }

    func waitUntilCaughtUp() async -> CollectorCatchupOutcome {
        guard let subscriptionHandle else { return .shutdown }
        let target = subscriptionHandle.deliveryCheckpoint()
        let waiterID = UUIDv7.generate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                guard self.subscriptionHandle != nil else {
                    continuation.resume(returning: .shutdown)
                    return
                }
                waiters[waiterID] = Waiter(target: target, continuation: continuation)
                resolveCaughtUpWaiters()
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelWaiter(waiterID)
            }
        }
    }

    func shutdown() async {
        let task = collectionTask
        collectionTask = nil
        subscriptionHandle = nil
        resolveAllWaiters(as: .shutdown)
        task?.cancel()
        await task?.value
    }

    private func record(_ envelope: RuntimeEnvelope, snapshotApplication: HeldStep<Void>) async {
        if case .worktree(let worktreeEnvelope) = envelope,
            case .gitWorkingDirectory(.snapshotChanged) = worktreeEnvelope.event
        {
            try? await snapshotApplication.arrive(())
            guard !Task.isCancelled else { return }
            snapshotCount += 1
        }
        handledEnvelopeCount &+= 1
        resolveCaughtUpWaiters()
    }

    private func streamDidEnd() {
        subscriptionHandle = nil
        resolveAllWaiters(as: .shutdown)
    }

    private func resolveCaughtUpWaiters() {
        guard let subscriptionHandle, !waiters.isEmpty else { return }
        let checkpoint = subscriptionHandle.deliveryCheckpoint()
        guard handledEnvelopeCount >= checkpoint.enqueuedCount else { return }
        let readyIDs = waiters.compactMap { waiterID, waiter in
            handledEnvelopeCount >= waiter.target.enqueuedCount ? waiterID : nil
        }
        for waiterID in readyIDs {
            waiters.removeValue(forKey: waiterID)?.continuation.resume(
                returning: .caughtUp(droppedEnvelopes: checkpoint.droppedCount)
            )
        }
    }

    private func resolveAllWaiters(as outcome: CollectorCatchupOutcome) {
        let pending = Array(waiters.values)
        waiters.removeAll(keepingCapacity: false)
        for waiter in pending {
            waiter.continuation.resume(returning: outcome)
        }
    }

    private func cancelWaiter(_ waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.continuation.resume(returning: .cancelled)
    }
}
