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
        id: UUID = UUIDv7.generate(),
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active,
        kind: PaneKind = .layout(drawer: Drawer())
    ) {
        var normalizedMetadata = metadata
        normalizedMetadata.paneId = PaneId(uuid: id)
        normalizedMetadata.contentType = Self.contentType(for: content)

        self.id = id
        self.content = content
        self.metadata = normalizedMetadata
        self.residency = residency
        self.kind = kind
    }

    // MARK: - Legacy Decoding

    /// Custom decoder supporting both the current schema (`kind: PaneKind`) and the
    /// legacy schema (`drawer: Drawer?`). Workspaces persisted before the PaneKind
    /// migration have no `kind` key — they store drawer state directly on Pane.
    /// This decoder reads `kind` first; if absent, falls back to the legacy `drawer`
    /// field and maps it to `.layout(drawer:)`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.content = try container.decode(PaneContent.self, forKey: .content)
        var decodedMetadata = try container.decode(PaneMetadata.self, forKey: .metadata)
        decodedMetadata.paneId = PaneId(uuid: id)
        decodedMetadata.contentType = Self.contentType(for: content)
        self.metadata = decodedMetadata
        self.residency = try container.decode(SessionResidency.self, forKey: .residency)

        if let kind = try container.decodeIfPresent(PaneKind.self, forKey: .kind) {
            // Current schema — kind is present
            self.kind = kind
        } else {
            // Legacy schema — read optional drawer field, default to empty drawer
            let drawer = try container.decodeIfPresent(Drawer.self, forKey: .legacyDrawer) ?? Drawer()
            self.kind = .layout(drawer: drawer)
        }
    }

    /// Encodes using the current schema only (writes `kind`, never the legacy `drawer` key).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(residency, forKey: .residency)
        try container.encode(kind, forKey: .kind)
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, metadata, residency, kind
        /// Legacy key: pre-PaneKind workspaces stored `drawer` directly on Pane.
        /// Keep this until we intentionally drop backward compatibility for old
        /// serialized workspaces.
        case legacyDrawer = "drawer"
    }

    // MARK: - Convenience Accessors

    /// The terminal state, if this pane holds terminal content.
    var terminalState: TerminalState? {
        if case .terminal(let state) = content { return state }
        return nil
    }

    /// The webview state, if this pane holds webview content.
    var webviewState: WebviewState? {
        if case .webview(let state) = content { return state }
        return nil
    }

    /// Source from metadata.
    var source: TerminalSource { metadata.terminalSource }

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

    private static func contentType(for content: PaneContent) -> PaneContentType {
        switch content {
        case .terminal:
            return .terminal
        case .webview:
            return .browser
        case .bridgePanel:
            return .plugin("bridgePanel")
        case .codeViewer:
            return .editor
        case .unsupported(let unsupported):
            return .plugin(unsupported.type)
        }
    }
}
