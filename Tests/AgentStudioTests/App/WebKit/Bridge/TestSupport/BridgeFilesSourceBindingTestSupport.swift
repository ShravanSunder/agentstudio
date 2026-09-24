import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@testable import AgentStudioBridge

extension BridgeFilesSourceBinding {
    /// A receiver collection of one worktree rooted at `rootURL`. Its rows are
    /// listed under the group named by `rootURL`'s last path component.
    static func testSingleWorktree(
        rootURL: URL,
        worktreeId: UUID = UUIDv7.generate(),
        repoId: UUID = UUIDv7.generate()
    ) -> Self {
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: rootURL.lastPathComponent,
            path: rootURL
        )
        return Self(
            collectionToken: Self.collectionToken(forReceiverPaneId: worktreeId),
            members: [worktree],
            openedDocuments: []
        )
    }
}
