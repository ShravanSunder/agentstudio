import Foundation

// MARK: - WorktreeOpenState

enum WorktreeOpenState: Equatable, Sendable {
    case notOpen
    case singlePane
    case multiplePanes
}

// MARK: - WorktreePresence

struct WorktreePresence: Equatable, Sendable {
    let worktreeId: UUID
    let repoId: UUID
    let worktreeName: String
    let repoName: String
    let isMainWorktree: Bool
    let openPanes: [WorkspacePaneLocation]

    var openState: WorktreeOpenState {
        switch openPanes.count {
        case 0:
            .notOpen
        case 1:
            .singlePane
        default:
            .multiplePanes
        }
    }

    var distinctTabCount: Int {
        Set(openPanes.map(\.tabId)).count
    }
}
