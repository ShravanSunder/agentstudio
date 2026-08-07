import Foundation
import Observation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct TargetedRepositoryCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    private final class ObservationInvalidationFlag: @unchecked Sendable {
        var didFire = false
    }

    @Test("targeted repository capability ignores unrelated pane and tab changes")
    func canExecuteRepositoryCommand_doesNotObservePaneOrTabState() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let repositoryPath = harness.tempDir.appending(path: "repository")
        let repository = harness.store.addRepo(at: repositoryPath)
        let worktree = try #require(repository.worktrees.first)
        let invalidation = ObservationInvalidationFlag()

        withObservationTracking {
            _ = harness.controller.canExecute(
                .openWorktree,
                target: worktree.id,
                targetType: .worktree
            )
            _ = harness.controller.canExecute(
                .openWorktreeInPane,
                target: worktree.id,
                targetType: .worktree
            )
            _ = harness.controller.canExecute(
                .openNewTerminalInTab,
                target: worktree.id,
                targetType: .worktree
            )
            _ = harness.controller.canExecute(
                .addRepoFavorite,
                target: repository.id,
                targetType: .repo
            )
            _ = harness.controller.canExecute(
                .removeRepoFavorite,
                target: repository.id,
                targetType: .repo
            )
        } onChange: {
            invalidation.didFire = true
        }

        let pane = harness.store.createPane()
        harness.store.appendTab(Tab(paneId: pane.id))

        #expect(!invalidation.didFire)
    }

    @Test("targeted repository capability validates indexed target membership")
    func canExecuteRepositoryCommand_validatesTargetMembership() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let repositoryPath = harness.tempDir.appending(path: "repository")
        let repository = harness.store.addRepo(at: repositoryPath)
        let worktree = try #require(repository.worktrees.first)

        for command in [AppCommand.openWorktree, .openWorktreeInPane, .openNewTerminalInTab] {
            #expect(
                harness.controller.canExecute(
                    command,
                    target: worktree.id,
                    targetType: .worktree
                )
            )
        }
        for command in [AppCommand.addRepoFavorite, .removeRepoFavorite] {
            #expect(
                harness.controller.canExecute(
                    command,
                    target: repository.id,
                    targetType: .repo
                )
            )
        }

        let staleTarget = UUIDv7.generate()
        #expect(
            !harness.controller.canExecute(
                .openWorktree,
                target: staleTarget,
                targetType: .worktree
            )
        )
        #expect(
            !harness.controller.canExecute(
                .addRepoFavorite,
                target: staleTarget,
                targetType: .repo
            )
        )
        #expect(
            !harness.controller.canExecute(
                .openWorktree,
                target: worktree.id,
                targetType: .repo
            )
        )
        #expect(
            !harness.controller.canExecute(
                .addRepoFavorite,
                target: repository.id,
                targetType: .worktree
            )
        )
    }
}
