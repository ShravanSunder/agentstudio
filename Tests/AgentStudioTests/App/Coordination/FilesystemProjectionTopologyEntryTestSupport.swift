import AgentStudioCore
import Foundation

extension FilesystemProjectionTopologyEntry {
    init(
        repoId: UUID,
        worktreeId: UUID,
        rootPath: URL,
        isUnavailable: Bool
    ) {
        self.init(
            repoId: repoId,
            repositoryStableKey: "test-repository-\(repoId.uuidString)",
            worktreeId: worktreeId,
            rootPath: rootPath,
            isUnavailable: isUnavailable
        )
    }
}
