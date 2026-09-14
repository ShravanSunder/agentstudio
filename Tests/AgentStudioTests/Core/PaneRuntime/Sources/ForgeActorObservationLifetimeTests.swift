import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Forge observation lifetime", .serialized)
struct ForgeActorObservationLifetimeTests {
    @Test("a provider result captured before hide-return cannot publish into the restored family")
    func lateProviderResultCannotCrossLifetime() async {
        let fixture = await ForgeActorFixture.make()
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let epoch = UUIDv7.generate()
        let oldLifetime = RepositoryObservationLifetime(launchEpoch: epoch, revision: 1)
        let newLifetime = RepositoryObservationLifetime(launchEpoch: epoch, revision: 2)
        await fixture.actor.assertObservationLifetimes(
            .init(
                generation: 1, contextsByWorktreeId: [:], repositoryLifetimes: [repositoryID: oldLifetime]
            ))
        await fixture.register(repoId: repositoryID, worktrees: [(worktreeID, "feature/lifetime")])
        await fixture.actor.setDemand(worktreeIds: [worktreeID])
        await assertEventuallyAsync("old request reaches provider") { await fixture.provider.callCount == 1 }

        await fixture.actor.assertObservationLifetimes(.init(generation: 2, contextsByWorktreeId: [:]))
        await fixture.actor.assertObservationLifetimes(
            .init(
                generation: 3, contextsByWorktreeId: [:], repositoryLifetimes: [repositoryID: newLifetime]
            ))
        let obsoleteURL = URL(string: "https://github.com/acme/studio/pull/999")!
        await fixture.provider.resolve(
            callAt: 0,
            with: .complete([
                ForgePullRequest(headRefName: "feature/lifetime", url: obsoleteURL)
            ]))
        await assertEventuallyAsync("restored lifetime starts a fresh request") {
            await fixture.provider.callCount == 2
        }
        await fixture.provider.resolveIfPresent(callAt: 1, with: .complete([]))
        await assertEventuallyAsync("only current facts reach the bus") {
            await fixture.events.facts(for: repositoryID, branch: "feature/lifetime")
                == PullRequestFacts(openCount: 0, exactOpenURL: nil)
        }

        #expect(await fixture.events.containsExactURL(obsoleteURL) == false)
        await fixture.actor.shutdown()
        await fixture.stopObserving()
    }
}
