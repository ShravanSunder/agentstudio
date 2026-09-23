import Foundation

/// Which of the two worktree-creation commands a request executes. Both are distinct
/// `AppCommand` identities; this is the typed argument-bearing form of the pair.
package enum WorktreeCreationKind: Equatable, Sendable {
    /// `git worktree add` on a new branch, checked out clean.
    case cleanCheckout
    /// APFS copy-on-write fork carrying uncommitted, untracked, and ignored files.
    case fork

    package init?(command: AppCommand) {
        switch command {
        case .newWorktree: self = .cleanCheckout
        case .forkWorktree: self = .fork
        default: return nil
        }
    }

    package var command: AppCommand {
        switch self {
        case .cleanCheckout: .newWorktree
        case .fork: .forkWorktree
        }
    }
}

/// The interactive creation request the command bar hands to the dispatcher. Both
/// kinds branch from the source worktree's HEAD.
package struct WorktreeCreationRequest: Equatable, Sendable {
    package let kind: WorktreeCreationKind
    package let sourceWorktreeId: UUID
    package let branchName: WorktreeBranchName

    package init(kind: WorktreeCreationKind, sourceWorktreeId: UUID, branchName: WorktreeBranchName) {
        self.kind = kind
        self.sourceWorktreeId = sourceWorktreeId
        self.branchName = branchName
    }
}
