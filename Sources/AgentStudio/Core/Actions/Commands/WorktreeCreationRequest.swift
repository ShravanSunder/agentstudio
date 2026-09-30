import AgentStudioWorktreeOperations
import Foundation

/// Creation operations reached from the New Worktree submenu.
package enum WorktreeCreationKind: Equatable, Sendable {
    /// `git worktree add` from the repository's default branch.
    case fromDefault
    /// `git worktree add` from a selected local branch reference.
    case fromBranch(referenceName: String)
    /// APFS copy-on-write fork carrying uncommitted, untracked, and ignored files.
    case fork

    package init?(command: AppCommand) {
        switch command {
        case .newWorktreeFromDefault: self = .fromDefault
        case .forkWorktree: self = .fork
        default: return nil
        }
    }

    package var command: AppCommand {
        switch self {
        case .fromDefault: .newWorktreeFromDefault
        case .fromBranch: .newWorktreeFromBranch
        case .fork: .forkWorktree
        }
    }
}

/// The target is a repository for branch creation and a source worktree for Fork.
package struct WorktreeCreationRequest: Equatable, Sendable {
    package let kind: WorktreeCreationKind
    package let targetId: UUID
    package let branchName: WorktreeBranchName

    package init(kind: WorktreeCreationKind, targetId: UUID, branchName: WorktreeBranchName) {
        self.kind = kind
        self.targetId = targetId
        self.branchName = branchName
    }

    package var targetType: SearchItemType {
        switch kind {
        case .fromDefault, .fromBranch: .repo
        case .fork: .worktree
        }
    }
}
