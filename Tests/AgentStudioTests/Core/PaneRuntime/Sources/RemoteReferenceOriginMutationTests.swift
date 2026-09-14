import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

extension RemoteReferenceRefreshActorTests {
    @Test("origin setter rejects stale repository observation lifetime")
    func originSetterRejectsStaleObservationLifetime() async {
        let fixture = RemoteReferenceRefreshFixture()
        let currentLifetime = RepositoryObservationLifetime(launchEpoch: UUIDv7.generate(), revision: 2)
        let staleLifetime = RepositoryObservationLifetime(
            launchEpoch: currentLifetime.launchEpoch,
            revision: 1
        )
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
            }
        )
        await actor.assertTopology(
            .init(
                generation: 1,
                contextsByWorktreeId: [
                    fixture.worktreeId: WorktreeFilesystemContext(
                        repoId: fixture.repoId,
                        rootPath: fixture.repositoryPath
                    )
                ],
                repositoryLifetimes: [fixture.repoId: currentLifetime]
            ))

        let staleMutationAccepted = await actor.setOrigin(
            repoId: fixture.repoId,
            expectedOrigin: fixture.originA,
            expectedLifetime: staleLifetime
        )
        #expect(!staleMutationAccepted)
        #expect(await fixture.acceptanceRecorder.localAcceptanceOrigins.isEmpty)

        let currentMutationAccepted = await actor.setOrigin(
            repoId: fixture.repoId,
            expectedOrigin: fixture.originA,
            expectedLifetime: currentLifetime
        )
        #expect(currentMutationAccepted)
        #expect(await fixture.acceptanceRecorder.localAcceptanceOrigins == [fixture.originA])

        let staleEqualMutationAccepted = await actor.setOrigin(
            repoId: fixture.repoId,
            expectedOrigin: fixture.originA,
            expectedLifetime: staleLifetime
        )
        #expect(!staleEqualMutationAccepted)
        await actor.shutdown()
    }

    @Test("origin setter cannot resurrect a registration retired during authority invalidation")
    func originSetterCannotResurrectRetiredRegistration() async {
        let fixture = RemoteReferenceRefreshFixture()
        let invalidationGate = RemoteReferenceOneShotInvalidationGate()
        let actor = RemoteReferenceRefreshActor(
            provider: fixture.provider,
            onAuthorityUpdate: { update in
                await fixture.acceptanceRecorder.record(update)
                if case .invalidated = update {
                    await invalidationGate.suspendNextInvalidation()
                }
            }
        )
        await actor.register(
            repoId: fixture.repoId,
            worktreeId: fixture.worktreeId,
            repositoryPath: fixture.repositoryPath,
            remoteName: "origin",
            expectedOrigin: fixture.originA
        )

        let originMutation = Task {
            await actor.setOrigin(repoId: fixture.repoId, expectedOrigin: fixture.originB)
        }
        await invalidationGate.waitUntilInvalidationSuspended()

        await actor.unregister(worktreeId: fixture.worktreeId, repoId: fixture.repoId)
        await invalidationGate.releaseInvalidation()
        await originMutation.value

        let admission = await actor.startExplicitRepositoryUpdate(
            repoId: fixture.repoId,
            attemptId: UUIDv7.generate()
        )
        #expect(admission.acceptedLease == nil)
        await actor.shutdown()
    }
}
