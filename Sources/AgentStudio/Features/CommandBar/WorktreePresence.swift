import Foundation

// MARK: - WorktreeOpenState

enum WorktreeOpenState: Equatable, Sendable {
    case notOpen
    case singlePane
    case multiplePanes
}

// MARK: - WorktreePaneLocation

struct WorktreePaneLocation: Equatable, Sendable {
    let paneId: UUID
    let tabId: UUID
    let tabIndex: Int
    let isActiveInTab: Bool
}

// MARK: - WorktreePresence

struct WorktreePresence: Equatable, Sendable {
    let worktreeId: UUID
    let repoId: UUID
    let worktreeName: String
    let repoName: String
    let isMainWorktree: Bool
    let openPanes: [WorktreePaneLocation]

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
