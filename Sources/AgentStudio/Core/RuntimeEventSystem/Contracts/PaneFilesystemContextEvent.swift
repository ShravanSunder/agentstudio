import Foundation

package struct PaneFilesystemContext: Sendable, Equatable {
    package let paneId: PaneId
    package let repoId: UUID
    package let cwd: URL
    package let worktreeId: WorktreeId

    package init(paneId: PaneId, repoId: UUID, cwd: URL, worktreeId: WorktreeId) {
        self.paneId = paneId
        self.repoId = repoId
        self.cwd = cwd
        self.worktreeId = worktreeId
    }
}

package enum PaneFilesystemContextEvent: PaneKindEvent, Sendable, Equatable {
    case cwdSubtreeChanged(context: PaneFilesystemContext, paths: Set<String>, batchSeq: UInt64)
    case gitWorkingTreeInCwd(context: PaneFilesystemContext, staged: Int, unstaged: Int, untracked: Int)

    package var actionPolicy: ActionPolicy { .critical }

    package var eventName: EventIdentifier {
        switch self {
        case .cwdSubtreeChanged:
            return .fsCwdSubtreeChanged
        case .gitWorkingTreeInCwd:
            return .fsGitWorkingTreeInCwd
        }
    }
}
