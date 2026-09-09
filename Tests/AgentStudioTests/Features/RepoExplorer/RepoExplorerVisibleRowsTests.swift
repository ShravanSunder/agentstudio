import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private final class VisibleWorktreeCallbackRecorder {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

@MainActor
@Suite("Repo Explorer viewport publication")
struct RepoExplorerVisibleRowsTests {
    @Test("typed native viewport replaces Git demand and invokes its existing callback")
    func typedNativeViewportReplacesGitDemandAndInvokesCallback() {
        let atom = SidebarVisibleWorktreesRuntimeAtom()
        let recorder = VisibleWorktreeCallbackRecorder()
        let firstWorktreeID = UUIDv7.generate()
        let secondWorktreeID = UUIDv7.generate()
        atom.setVisibleWorktreeIds([firstWorktreeID])
        let snapshot = RepoExplorerVisibleWorktreeSnapshot(
            target: RepoExplorerCommandPresentationTarget(
                materializationHostLifetimeID: RepoExplorerMaterializationHostLifetimeID(
                    rawValue: UUIDv7.generate()
                ),
                materializationGeneration: 7,
                visibleRevision: 3
            ),
            worktreeIDs: [secondWorktreeID]
        )

        RepoExplorerViewportPublisher.publish(
            snapshot,
            into: atom,
            onChange: recorder.record
        )

        #expect(atom.visibleWorktreeIds == [secondWorktreeID])
        #expect(recorder.callCount == 1)
    }
}
