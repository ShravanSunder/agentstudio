import Foundation

/// The primary entity in the window system. Replaces TerminalSession as the universal identity.
/// `id` (paneId) is the single identity used across all layers: WorkspaceStore, Layout,
/// ViewRegistry, SurfaceManager, SessionRuntime, and tmux.
struct Pane: Codable, Identifiable, Hashable {
    let id: UUID
    /// The content displayed in this pane.
    var content: PaneContent
    /// Metadata for context tracking and dynamic grouping.
    var metadata: PaneMetadata
    /// Lifecycle residency state (active, pendingUndo, backgrounded).
    var residency: SessionResidency
    /// Optional drawer holding child panes. Always nil in Phase A.
    var drawer: Drawer?

    init(
        id: UUID = UUID(),
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active,
        drawer: Drawer? = nil
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.residency = residency
        self.drawer = drawer
    }

    // MARK: - Convenience Accessors

    /// The terminal state, if this pane holds terminal content.
    var terminalState: TerminalState? {
        if case .terminal(let state) = content { return state }
        return nil
    }

    /// Source from metadata.
    var source: TerminalSource { metadata.source }

    /// Title from metadata.
    var title: String {
        get { metadata.title }
        set { metadata.title = newValue }
    }

    /// Agent type from metadata.
    var agent: AgentType? {
        get { metadata.agentType }
        set { metadata.agentType = newValue }
    }

    /// Provider from terminal state, if terminal content.
    var provider: SessionProvider? { terminalState?.provider }

    /// Lifetime from terminal state, if terminal content.
    var lifetime: SessionLifetime? { terminalState?.lifetime }

    var worktreeId: UUID? { metadata.worktreeId }
    var repoId: UUID? { metadata.repoId }
}
