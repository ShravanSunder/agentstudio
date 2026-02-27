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
        let normalizedMetadata = metadata.canonicalizedIdentity(
            paneId: PaneId(uuid: id),
            contentType: Self.contentType(for: content)
        )

        self.id = id
        self.content = content
        self.metadata = normalizedMetadata
        self.residency = residency
        self.kind = kind
    }

    // MARK: - Codable

    /// Canonical greenfield decode: only the current `kind: PaneKind` schema is accepted.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decode(UUID.self, forKey: .id)
        guard UUIDv7.isV7(decodedId) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Pane.id must be UUID v7 in canonical greenfield schema"
            )
        }
        self.id = decodedId
        self.content = try container.decode(PaneContent.self, forKey: .content)
        let decodedMetadata = try container.decode(PaneMetadata.self, forKey: .metadata)
        let metadataPaneId = decodedMetadata.paneId.uuid
        guard metadataPaneId == decodedId else {
            let mismatchDescription =
                "Pane.metadata.paneId (\(metadataPaneId.uuidString)) must match "
                + "Pane.id (\(decodedId.uuidString)) in canonical schema"
            throw DecodingError.dataCorruptedError(
                forKey: .metadata,
                in: container,
                debugDescription: mismatchDescription
            )
        }
        self.metadata = decodedMetadata.canonicalizedIdentity(
            paneId: PaneId(uuid: id),
            contentType: Self.contentType(for: content)
        )
        self.residency = try container.decode(SessionResidency.self, forKey: .residency)
        self.kind = try container.decode(PaneKind.self, forKey: .kind)
    }

    /// Encodes using the canonical schema.
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
        set { metadata.updateTitle(newValue) }
    }

    /// Agent type from metadata.
    var agent: AgentType? {
        get { metadata.agentType }
        set { metadata.updateAgentType(newValue) }
    }

    /// Provider from terminal state, if terminal content.
    var provider: SessionProvider? { terminalState?.provider }

    /// Lifetime from terminal state, if terminal content.
    var lifetime: SessionLifetime? { terminalState?.lifetime }

    var worktreeId: UUID? { metadata.facets.worktreeId }
    var repoId: UUID? { metadata.facets.repoId }

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
        case .bridgePanel(let bridgeState):
            switch bridgeState.panelKind {
            case .diffViewer:
                return .diff
            }
        case .codeViewer:
            return .codeViewer
        case .unsupported(let unsupported):
            return .plugin(unsupported.type)
        }
    }
}
