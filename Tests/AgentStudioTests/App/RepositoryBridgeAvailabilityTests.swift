import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repository Bridge availability", .serialized)
struct RepositoryBridgeAvailabilityTests {
    @Test("Bridge target and fallback authority exclude hidden checkouts", arguments: [true, false])
    func bridgeAuthorityExcludesUnavailableLocations(hasAvailableSibling: Bool) async throws {
        try await withAsyncTestCoreAtoms { _ in
            let harness = makeHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            try await withWorkspaceCommandHarness(harness) {
                let repository = harness.store.addRepo(at: harness.tempDir.appending(path: "repository"))
                let main = try #require(repository.worktrees.first)
                let target: Worktree
                if hasAvailableSibling {
                    target = Worktree(
                        id: UUIDv7.generate(), repoId: repository.id, name: "linked",
                        path: harness.tempDir.appending(path: "linked"))
                    _ = harness.store.mutationCoordinator.reconcileDiscoveredWorktrees(
                        repository.id, worktrees: [main, target])
                } else {
                    target = main
                }
                #expect(
                    harness.store.mutationCoordinator.recordWorktreeAbsence(
                        target.id,
                        at: .init(utc: Date(timeIntervalSince1970: 1000), bootID: "fixture", uptimeNanoseconds: 1)))

                for command in [
                    AppCommand.showBridgeFiles, .showBridgeReview, .openBridgeFilesInNewTab, .openBridgeReviewInNewTab,
                ] {
                    #expect(!harness.controller.canExecute(command, target: target.id, targetType: .worktree))
                }
                #expect(harness.coordinator.resolveBridgePaneCommand(worktreeId: target.id) == nil)
                if hasAvailableSibling {
                    #expect(
                        harness.controller.canExecute(.openBridgeFilesInNewTab, target: main.id, targetType: .worktree))
                    #expect(harness.coordinator.resolveBridgePaneCommand(worktreeId: main.id) != nil)
                } else {
                    #expect(harness.coordinator.resolveBridgePaneCommand() == nil)
                }
            }
        }
    }
}
