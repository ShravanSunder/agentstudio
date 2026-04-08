import Foundation

struct PaneFilesystemContext: Sendable, Equatable {
    let paneId: PaneId
    let cwd: URL
    let worktreeId: WorktreeId
}

enum PaneFilesystemContextEvent: PaneKindEvent, Sendable, Equatable {
    case cwdSubtreeChanged(context: PaneFilesystemContext, paths: Set<String>, batchSeq: UInt64)
    case gitWorkingTreeInCwd(context: PaneFilesystemContext, staged: Int, unstaged: Int, untracked: Int)

    var actionPolicy: ActionPolicy { .critical }

    var eventName: EventIdentifier {
        switch self {
        case .cwdSubtreeChanged:
            return .plugin("fs.cwdSubtreeChanged")
        case .gitWorkingTreeInCwd:
            return .plugin("fs.gitWorkingTreeInCwd")
        }
    }
}
