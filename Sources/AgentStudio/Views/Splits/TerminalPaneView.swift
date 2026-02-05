import Foundation

/// Represents a single terminal pane in a split tree.
/// This is a lightweight identifier - the actual terminal view is managed separately.
struct TerminalPaneView: Identifiable, Codable, Equatable {
    let id: UUID
    let worktreeId: UUID
    let projectId: UUID

    /// Title to display (worktree name)
    var title: String

    init(id: UUID = UUID(), worktreeId: UUID, projectId: UUID, title: String) {
        self.id = id
        self.worktreeId = worktreeId
        self.projectId = projectId
        self.title = title
    }
}

/// Type alias for the split tree used in Agent Studio
typealias TerminalSplitTree = SplitTree<TerminalPaneView>
