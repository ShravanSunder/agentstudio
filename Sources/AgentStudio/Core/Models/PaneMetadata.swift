import Foundation

/// Metadata carried by every Pane for context tracking and dynamic grouping.
struct PaneMetadata: Codable, Hashable {
    /// Origin: worktree or floating.
    var source: TerminalSource
    /// Display title for the pane.
    var title: String
    /// Live current working directory (propagated from terminal).
    var cwd: URL?
    /// Agent running in this pane, if any.
    var agentType: AgentType?
    /// User-defined or auto-detected labels for dynamic grouping.
    var tags: [String]

    init(
        source: TerminalSource,
        title: String = "Terminal",
        cwd: URL? = nil,
        agentType: AgentType? = nil,
        tags: [String] = []
    ) {
        self.source = source
        self.title = title
        self.cwd = cwd
        self.agentType = agentType
        self.tags = tags
    }

    // MARK: - Convenience Accessors

    var worktreeId: UUID? {
        if case .worktree(let id, _) = source { return id }
        return nil
    }

    var repoId: UUID? {
        if case .worktree(_, let id) = source { return id }
        return nil
    }
}
