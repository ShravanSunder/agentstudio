import Testing

@testable import AgentStudio

@Suite("Bridge worktree product construction coordinator")
struct BridgeWorktreeProductConstructionCoordinatorTests {
    @Test("exact duplicates single-flight one build and receive independent leases")
    func exactDuplicatesSingleFlight() async throws {
        // Arrange
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        let coordinator = BridgeWorktreeProductConstructionCoordinator(eventSink: eventProbe.eventSink)
        let key = makeBridgeFileConstructionKey()
        let gate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeFileConstructionArtifact())
        let first = Task { try await coordinator.acquire(key: key, build: gate.run) }
        await gate.waitUntilStarted()

        // Act
        let second = Task { try await coordinator.acquire(key: key, build: gate.run) }
        _ = await eventProbe.waitFor(.consumerJoined)
        await gate.release()
        let firstLease = try await first.value
        let secondLease = try await second.value

        // Assert
        #expect(await gate.recordedInvocationCount() == 1)
        #expect(firstLease.entryNonce == secondLease.entryNonce)
        #expect(firstLease.leaseNonce != secondLease.leaseNonce)
        await coordinator.release(firstLease)
        let peerSnapshot = await coordinator.snapshot()
        #expect(peerSnapshot.leaseCount == 1)
        #expect(peerSnapshot.payloadCount == 1)
        await coordinator.release(secondLease)

        let reopenGate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeFileConstructionArtifact())
        let reopenTask = Task { try await coordinator.acquire(key: key, build: reopenGate.run) }
        await reopenGate.waitUntilStarted()
        await reopenGate.release()
        let reopenedLease = try await reopenTask.value
        #expect(reopenedLease.entryNonce != firstLease.entryNonce)
        await coordinator.release(reopenedLease)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("exact review duplicates receive independent leases over one template build")
    func exactReviewDuplicatesSingleFlight() async throws {
        // Arrange
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        let coordinator = BridgeWorktreeProductConstructionCoordinator(eventSink: eventProbe.eventSink)
        let key = makeBridgeReviewConstructionKey()
        let gate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeReviewConstructionArtifact())
        let first = Task { try await coordinator.acquire(key: key, build: gate.run) }
        await gate.waitUntilStarted()

        // Act
        let second = Task { try await coordinator.acquire(key: key, build: gate.run) }
        _ = await eventProbe.waitFor(.consumerJoined)
        await gate.release()
        let firstLease = try await first.value
        let secondLease = try await second.value

        // Assert
        #expect(await gate.recordedInvocationCount() == 1)
        #expect(firstLease.entryNonce == secondLease.entryNonce)
        #expect(firstLease.leaseNonce != secondLease.leaseNonce)
        await coordinator.release(firstLease)
        await coordinator.release(secondLease)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("one-field-different keys and different worktrees construct independently")
    func distinctSemanticKeysDoNotShare() async throws {
        // Arrange
        let coordinator = BridgeWorktreeProductConstructionCoordinator()
        let baseGate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeFileConstructionArtifact())
        let selectorGate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeFileConstructionArtifact()
        )
        let worktreeGate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeFileConstructionArtifact()
        )

        // Act
        let baseTask = Task {
            try await coordinator.acquire(key: makeBridgeFileConstructionKey(), build: baseGate.run)
        }
        let selectorTask = Task {
            try await coordinator.acquire(
                key: makeBridgeFileConstructionKey(pathScope: ["Tests"]),
                build: selectorGate.run
            )
        }
        let worktreeTask = Task {
            try await coordinator.acquire(
                key: makeBridgeFileConstructionKey(
                    owner: makeBridgeConstructionOwner(worktree: "worktree-b")
                ),
                build: worktreeGate.run
            )
        }
        await baseGate.waitUntilStarted()
        await selectorGate.waitUntilStarted()
        await worktreeGate.waitUntilStarted()
        await baseGate.release()
        await selectorGate.release()
        await worktreeGate.release()
        let leases = try await [baseTask.value, selectorTask.value, worktreeTask.value]

        // Assert
        #expect(await baseGate.recordedInvocationCount() == 1)
        #expect(await selectorGate.recordedInvocationCount() == 1)
        #expect(await worktreeGate.recordedInvocationCount() == 1)
        #expect(Set(leases.map(\.entryNonce)).count == 3)
        for lease in leases {
            await coordinator.release(lease)
        }
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("provider-specific entries share one canonical worktree freshness epoch")
    func providerEntriesShareWorktreeInvalidation() async throws {
        // Arrange
        let coordinator = BridgeWorktreeProductConstructionCoordinator()
        let providerAKey = makeBridgeFileConstructionKey()
        let providerBKey = makeBridgeFileConstructionKey(
            owner: makeBridgeConstructionOwner(provider: "provider-b")
        )
        let providerAGate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeFileConstructionArtifact()
        )
        let providerBGate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeFileConstructionArtifact()
        )
        let oldProviderA = Task {
            try await coordinator.acquire(key: providerAKey, build: providerAGate.run)
        }
        let oldProviderB = Task {
            try await coordinator.acquire(key: providerBKey, build: providerBGate.run)
        }
        await providerAGate.waitUntilStarted()
        await providerBGate.waitUntilStarted()

        // Act
        let advancedEpoch = await coordinator.invalidate(worktree: providerAKey.worktree)
        let oldProviderAResult = await oldProviderA.result
        let oldProviderBResult = await oldProviderB.result
        let currentProviderA = Task {
            try await coordinator.acquire(key: providerAKey, build: providerAGate.run)
        }
        let currentProviderB = Task {
            try await coordinator.acquire(key: providerBKey, build: providerBGate.run)
        }
        await providerAGate.waitUntilStarted(count: 2)
        await providerBGate.waitUntilStarted(count: 2)
        await providerAGate.release(invocation: 1)
        await providerBGate.release(invocation: 1)
        await providerAGate.release(invocation: 2)
        await providerBGate.release(invocation: 2)
        let currentProviderALease = try await currentProviderA.value
        let currentProviderBLease = try await currentProviderB.value

        // Assert
        guard case .failure(let providerAError) = oldProviderAResult,
            case .failure(let providerBError) = oldProviderBResult
        else {
            Issue.record("provider-specific old epochs unexpectedly published")
            return
        }
        #expect(providerAError as? BridgeWorktreeProductConstructionError == .invalidated)
        #expect(providerBError as? BridgeWorktreeProductConstructionError == .invalidated)
        #expect(advancedEpoch.rawValue == 2)
        #expect(currentProviderALease.epoch == advancedEpoch)
        #expect(currentProviderBLease.epoch == advancedEpoch)
        #expect(currentProviderALease.entryNonce != currentProviderBLease.entryNonce)
        #expect(await providerAGate.recordedInvocationCount() == 2)
        #expect(await providerBGate.recordedInvocationCount() == 2)
        await coordinator.release(currentProviderALease)
        await coordinator.release(currentProviderBLease)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("one consumer cancellation does not cancel or poison its peer")
    func cancellationIsolation() async throws {
        // Arrange
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        let coordinator = BridgeWorktreeProductConstructionCoordinator(eventSink: eventProbe.eventSink)
        let key = makeBridgeReviewConstructionKey()
        let gate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeReviewConstructionArtifact())
        let cancelled = Task { try await coordinator.acquire(key: key, build: gate.run) }
        await gate.waitUntilStarted()
        let peer = Task { try await coordinator.acquire(key: key, build: gate.run) }
        _ = await eventProbe.waitFor(.consumerJoined)

        // Act
        cancelled.cancel()
        _ = await eventProbe.waitFor(.consumerCancelled)
        await gate.release()
        let cancelledResult = await cancelled.result
        let peerLease = try await peer.value

        // Assert
        guard case .failure(let error) = cancelledResult else {
            Issue.record("cancelled consumer unexpectedly acquired a lease")
            return
        }
        #expect(error is CancellationError)
        #expect(await gate.recordedInvocationCount() == 1)
        await coordinator.release(peerLease)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("failures are never cached")
    func failureIsNotCached() async throws {
        enum ExpectedFailure: Error { case failed }
        actor InvocationCounter {
            var count = 0
            func fail(_: BridgeWorktreeProductConstructionContext) throws -> BridgeWorktreeProductConstructionArtifact {
                count += 1
                throw ExpectedFailure.failed
            }
            func succeed(_: BridgeWorktreeProductConstructionContext) -> BridgeWorktreeProductConstructionArtifact {
                count += 1
                return makeBridgeFileConstructionArtifact()
            }
        }

        // Arrange
        let coordinator = BridgeWorktreeProductConstructionCoordinator()
        let key = makeBridgeFileConstructionKey()
        let counter = InvocationCounter()

        // Act
        let firstResult = await Task {
            try await coordinator.acquire(key: key) { context in
                try await counter.fail(context)
            }
        }.result
        let lease = try await coordinator.acquire(key: key) { context in
            await counter.succeed(context)
        }

        // Assert
        guard case .failure(let error) = firstResult else {
            Issue.record("failing build unexpectedly acquired a lease")
            return
        }
        #expect(error is ExpectedFailure)
        #expect(await counter.count == 2)
        await coordinator.release(lease)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("invalidation stale-drops held completion and single-flights current rebuild")
    func invalidationDropsStaleCompletion() async throws {
        // Arrange
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        let coordinator = BridgeWorktreeProductConstructionCoordinator(eventSink: eventProbe.eventSink)
        let key = makeBridgeReviewConstructionKey()
        let worktree = key.worktree
        let gate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeReviewConstructionArtifact())
        let old = Task { try await coordinator.acquire(key: key, build: gate.run) }
        await gate.waitUntilStarted()

        // Act
        let newEpoch = await coordinator.invalidate(worktree: worktree)
        let oldResult = await old.result
        let currentA = Task { try await coordinator.acquire(key: key, build: gate.run) }
        await gate.waitUntilStarted(count: 2)
        let currentB = Task { try await coordinator.acquire(key: key, build: gate.run) }
        _ = await eventProbe.waitFor(.consumerJoined)
        await gate.release(invocation: 1)
        _ = await eventProbe.waitFor(.staleCompletionDropped)
        await gate.release(invocation: 2)
        let leaseA = try await currentA.value
        let leaseB = try await currentB.value

        // Assert
        guard case .failure(let error) = oldResult else {
            Issue.record("old epoch unexpectedly published")
            return
        }
        #expect(error as? BridgeWorktreeProductConstructionError == .invalidated)
        #expect(newEpoch.rawValue == 2)
        #expect(leaseA.epoch == newEpoch)
        #expect(leaseA.entryNonce == leaseB.entryNonce)
        #expect(await gate.recordedInvocationCount() == 2)
        await coordinator.release(leaseA)
        await coordinator.release(leaseB)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("close last creates a tombstone and reopen cannot attach across ABA")
    func closeLastAndReopenAreNonceFenced() async throws {
        // Arrange
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        let coordinator = BridgeWorktreeProductConstructionCoordinator(eventSink: eventProbe.eventSink)
        let key = makeBridgeFileConstructionKey()
        let gate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeFileConstructionArtifact())
        let closing = Task { try await coordinator.acquire(key: key, build: gate.run) }
        await gate.waitUntilStarted()

        // Act
        closing.cancel()
        let tombstoneEvent = await eventProbe.waitFor(.tombstoneCreated)
        let reopened = Task { try await coordinator.acquire(key: key, build: gate.run) }
        await gate.waitUntilStarted(count: 2)
        let reopenStart = await eventProbe.waitFor(.buildStarted, occurrence: 2)
        await gate.release(invocation: 1)
        _ = await eventProbe.waitFor(.staleCompletionDropped)
        await gate.release(invocation: 2)
        let reopenedLease = try await reopened.value

        // Assert
        #expect(tombstoneEvent.entryNonce != reopenStart.entryNonce)
        #expect(reopenedLease.entryNonce == reopenStart.entryNonce)
        guard case .failure(let error) = await closing.result else {
            Issue.record("closing consumer unexpectedly acquired a lease")
            return
        }
        #expect(error is CancellationError)
        await coordinator.release(reopenedLease)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }

    @Test("ready old review artifact remains readable while current epoch constructs")
    func oldReadyArtifactRemainsReadable() async throws {
        // Arrange
        let coordinator = BridgeWorktreeProductConstructionCoordinator()
        let key = makeBridgeReviewConstructionKey()
        let oldGate = BridgeWorktreeProductConstructionGate(artifact: makeBridgeReviewConstructionArtifact())
        let oldTask = Task { try await coordinator.acquire(key: key, build: oldGate.run) }
        await oldGate.waitUntilStarted()
        await oldGate.release()
        let oldLease = try await oldTask.value
        _ = await coordinator.invalidate(worktree: key.worktree)
        let newGate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeReviewConstructionArtifact(retainedByteCount: 256))

        // Act
        let currentTask = Task { try await coordinator.acquire(key: key, build: newGate.run) }
        await newGate.waitUntilStarted()
        let concurrentSnapshot = await coordinator.snapshot()

        // Assert
        guard case .reviewTemplate(let oldTemplate) = oldLease.artifact else {
            Issue.record("old lease did not retain its review template")
            return
        }
        #expect(oldTemplate.contentLocatorCount == 2)
        #expect(concurrentSnapshot.leaseCount == 1)
        #expect(concurrentSnapshot.inFlightCount == 1)
        #expect(concurrentSnapshot.locatorCount == 2)
        await coordinator.release(oldLease)
        await newGate.release()
        let currentLease = try await currentTask.value
        #expect(currentLease.epoch.rawValue == 2)
        await coordinator.release(currentLease)
        await assertBridgeConstructionCoordinatorDrained(coordinator)
    }
}
