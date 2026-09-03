import AgentStudioInfrastructure
import Testing

@testable import AgentStudioCore

@Suite("Remote reference recomputation settlement")
struct RemoteReferenceRefreshRecomputationTests {
    @Test("explicit repository update remains admitted through represented worktree recomputation")
    func explicitRepositoryUpdateWaitsForRepresentedWorktreeRecomputation() async throws {
        let fixture = RemoteReferenceRefreshFixture()
        let performanceRecorder = RemoteReferencePerformanceRecorderSpy()
        let recomputationGate = RemoteReferenceRecomputationGate()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            performanceRecorder: performanceRecorder,
            onPromotedRecomputation: { _ in
                await recomputationGate.waitForRelease()
            }
        )
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )

        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: fixture.repoId,
            attemptId: UUIDv7.generate()
        )
        let lease = try #require(admission.acceptedLease)
        await recomputationGate.waitUntilEntered()

        #expect(performanceRecorder.combinedSnapshot.explicitSettledFailed == 0)
        #expect(performanceRecorder.settlements.last?.physicalActive == 1)

        await recomputationGate.release(with: .failed)
        #expect(await lease.settlement() == .failed)
        await actor.waitUntilIdle()
        #expect(performanceRecorder.combinedSnapshot.explicitSettledFailed == 1)
        #expect(performanceRecorder.settlements.last?.physicalActive == 0)

        await actor.shutdown()
    }

    @Test("automatic recomputation retains physical custody after demand contracts")
    func automaticRecomputationRetainsCustodyAfterDemandContracts() async {
        let fixture = RemoteReferenceRefreshFixture()
        let performanceRecorder = RemoteReferencePerformanceRecorderSpy()
        let recomputationGate = RemoteReferenceRecomputationGate()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            performanceRecorder: performanceRecorder,
            onPromotedRecomputation: { _ in
                await recomputationGate.waitForRelease()
            }
        )
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        await actor.setDemand(repositoryIds: [fixture.repoId])
        await recomputationGate.waitUntilEntered()

        await actor.setDemand(repositoryIds: [])

        #expect(performanceRecorder.settlements.last?.physicalActive == 1)
        await recomputationGate.release(with: .completed)
        await actor.waitUntilIdle()
        #expect(performanceRecorder.settlements.last?.physicalActive == 0)
        await actor.shutdown()
    }

    @Test("origin replacement during authority application cannot resurrect physical custody")
    func originReplacementDuringAuthorityApplicationCannotResurrectCustody() async throws {
        let fixture = RemoteReferenceRefreshFixture()
        let authorityGate = RemoteReferenceAuthorityApplicationGate()
        let performanceRecorder = RemoteReferencePerformanceRecorderSpy()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            performanceRecorder: performanceRecorder,
            onAuthorityUpdate: { update in
                guard case .promoted = update else { return }
                await authorityGate.waitForRelease()
            }
        )
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: fixture.repoId,
            attemptId: UUIDv7.generate()
        )
        let lease = try #require(admission.acceptedLease)
        await authorityGate.waitUntilEntered()

        await actor.setOrigin(repoId: fixture.repoId, expectedOrigin: fixture.originB)
        await authorityGate.release()

        #expect(await lease.settlement() == .obsolete)
        await actor.waitUntilIdle()
        #expect(performanceRecorder.settlements.last?.physicalActive == 0)
        await actor.shutdown()
    }

    @Test("shutdown during authority application cannot resurrect physical custody")
    func shutdownDuringAuthorityApplicationCannotResurrectCustody() async throws {
        let fixture = RemoteReferenceRefreshFixture()
        let authorityGate = RemoteReferenceAuthorityApplicationGate()
        let performanceRecorder = RemoteReferencePerformanceRecorderSpy()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            performanceRecorder: performanceRecorder,
            onAuthorityUpdate: { update in
                guard case .promoted = update else { return }
                await authorityGate.waitForRelease()
            }
        )
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: fixture.repoId,
            attemptId: UUIDv7.generate()
        )
        let lease = try #require(admission.acceptedLease)
        await authorityGate.waitUntilEntered()

        await actor.shutdown()
        await authorityGate.release()

        #expect(await lease.settlement() == .cancelled)
        await actor.waitUntilIdle()
        #expect(performanceRecorder.settlements.last?.physicalActive == 0)
    }

    @Test("final unregister invalidates before a ready promotion can publish")
    func finalUnregisterInvalidatesBeforeReadyPromotionPublishes() async throws {
        let fixture = RemoteReferenceRefreshFixture(suspendPromotion: true)
        let invalidationGate = RemoteReferenceAuthorityApplicationGate()
        let performanceRecorder = RemoteReferencePerformanceRecorderSpy()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            performanceRecorder: performanceRecorder,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
                guard case .invalidated = update else { return }
                await invalidationGate.waitForRelease()
            }
        )
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )
        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: fixture.repoId,
            attemptId: UUIDv7.generate()
        )
        let lease = try #require(admission.acceptedLease)
        await fixture.provider.waitUntilPromotionSuspended()
        let unregisterTask = Task {
            await actor.unregister(worktreeId: fixture.worktreeId, repoId: fixture.repoId)
        }
        await invalidationGate.waitUntilEntered()

        await fixture.provider.releasePromotion()
        for _ in 0..<1000 where performanceRecorder.combinedSnapshot.promotionCompleted == 0 {
            await actor.flushPerformanceSnapshot()
            await Task.yield()
        }

        #expect(performanceRecorder.combinedSnapshot.promotionCompleted == 1)
        #expect(await fixture.acceptanceRecorder.acceptanceCount == 0)
        await invalidationGate.release()
        await unregisterTask.value
        #expect(await lease.settlement() == .obsolete)
        await actor.waitUntilIdle()
        #expect(performanceRecorder.settlements.last?.physicalActive == 0)
        await actor.shutdown()
    }
}

private actor RemoteReferenceRecomputationGate {
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<RepositoryFactSourceUpdateOutcome, Never>?

    func waitForRelease() async -> RepositoryFactSourceUpdateOutcome {
        hasEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release(with outcome: RepositoryFactSourceUpdateOutcome) {
        releaseContinuation?.resume(returning: outcome)
        releaseContinuation = nil
    }
}

private actor RemoteReferenceAuthorityApplicationGate {
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        hasEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
