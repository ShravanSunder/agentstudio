import Foundation

/// Discriminated union for the origin/source of a terminal pane.
/// Each pane in a split tree carries a TerminalSource indicating
/// whether it's tied to a worktree or is a standalone floating terminal.
enum TerminalSource: Codable, Hashable {
    /// Terminal associated with a specific worktree in a repo
    case worktree(worktreeId: UUID, repoId: UUID)

    /// Standalone floating terminal not tied to any worktree
    case floating(workingDirectory: URL?, title: String?)
}
