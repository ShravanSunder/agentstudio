import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerRepoFavoriteCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("targeted repo favorite commands mutate canonical topology through workspace actions")
    func executeRepoFavoriteCommandsMutatesCanonicalTopology() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let (repo, _) = makeRepoAndWorktree(harness.store, root: harness.tempDir)

        harness.controller.execute(.addRepoFavorite, target: repo.id, targetType: .repo)

        #expect(harness.store.repositoryTopologyAtom.repo(repo.id)?.isFavorite == true)

        harness.controller.execute(.removeRepoFavorite, target: repo.id, targetType: .repo)

        #expect(harness.store.repositoryTopologyAtom.repo(repo.id)?.isFavorite == false)
    }
}
