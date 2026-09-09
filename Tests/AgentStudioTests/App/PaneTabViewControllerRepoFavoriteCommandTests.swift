import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerRepoFavoriteCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("targeted repo favorite commands mutate canonical topology through workspace actions")
    func executeRepoFavoriteCommandsMutatesCanonicalTopology() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        await withWorkspaceCommandHarness(harness) {
            let (repo, _) = makeRepoAndWorktree(harness.store, root: harness.tempDir)

            harness.controller.execute(.addRepoFavorite, target: repo.id, targetType: .repo)
            _ = await harness.executor.submitGesture { _ in true }.value

            #expect(harness.store.repositoryTopologyAtom.repo(repo.id)?.isFavorite == true)

            harness.controller.execute(.removeRepoFavorite, target: repo.id, targetType: .repo)
            _ = await harness.executor.submitGesture { _ in true }.value

            #expect(harness.store.repositoryTopologyAtom.repo(repo.id)?.isFavorite == false)
        }
    }
}
