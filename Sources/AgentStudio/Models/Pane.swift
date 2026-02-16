import Foundation

/// Discriminant union encoding a pane's container context.
/// Layout panes always have a drawer. Drawer children never do.
enum PaneKind: Codable, Hashable {
    /// Top-level pane in a tab's layout tree. Always has a drawer container.
    case layout(drawer: Drawer)
    /// Child pane inside a drawer. Knows its parent. Cannot have a sub-drawer.
    case drawerChild(parentPaneId: UUID)
}

/// The primary entity in the window system. Replaces TerminalSession as the universal identity.
/// `id` (paneId) is the single identity used across all layers: WorkspaceStore, Layout,
/// ViewRegistry, SurfaceManager, SessionRuntime, and zmx.
struct Pane: Codable, Identifiable, Hashable {
    let id: UUID
    /// The content displayed in this pane.
    var content: PaneContent
    /// Metadata for context tracking and dynamic grouping.
    var metadata: PaneMetadata
    /// Lifecycle residency state (active, pendingUndo, backgrounded).
    var residency: SessionResidency
    /// Discriminant — encodes whether this is a layout pane or drawer child.
    var kind: PaneKind

    init(
        id: UUID = UUID(),
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active,
        kind: PaneKind = .layout(drawer: Drawer())
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.residency = residency
        self.kind = kind
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

    // MARK: - PaneKind Convenience

    /// The drawer, if this is a layout pane.
    var drawer: Drawer? {
        if case .layout(let drawer) = kind { return drawer }
        return nil
    }

    /// Mutate the drawer in-place. No-op if this is a drawer child.
    mutating func withDrawer(_ transform: (inout Drawer) -> Void) {
        guard case .layout(var drawer) = kind else { return }
        transform(&drawer)
        kind = .layout(drawer: drawer)
    }

    /// Whether this pane is a drawer child.
    var isDrawerChild: Bool {
        if case .drawerChild = kind { return true }
        return false
    }

    /// The parent pane ID, if this is a drawer child.
    var parentPaneId: UUID? {
        if case .drawerChild(let parentId) = kind { return parentId }
        return nil
    }
}
