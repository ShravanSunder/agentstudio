import Foundation

/// A tab within a view. Contains a layout of sessions and tracks which session is focused.
/// Order is implicit — determined by array position in the parent ViewDefinition.tabs.
struct Tab: Codable, Identifiable, Hashable {
    let id: UUID
    var layout: Layout
    /// The focused session within this tab. Nil only during construction.
    var activeSessionId: UUID?
    /// Display-only zoom state — NOT persisted. When set, the zoomed session fills the tab.
    var zoomedSessionId: UUID?

    enum CodingKeys: CodingKey {
        case id, layout, activeSessionId
        // zoomedSessionId excluded — transient, not persisted
    }

    /// Create a tab with a single session.
    init(id: UUID = UUID(), sessionId: UUID) {
        self.id = id
        self.layout = Layout(sessionId: sessionId)
        self.activeSessionId = sessionId
        self.zoomedSessionId = nil
    }

    /// Create a tab with an existing layout.
    init(id: UUID = UUID(), layout: Layout, activeSessionId: UUID?, zoomedSessionId: UUID? = nil) {
        self.id = id
        self.layout = layout
        self.activeSessionId = activeSessionId
        self.zoomedSessionId = zoomedSessionId
    }

    // MARK: - Derived

    /// All session IDs in this tab's layout (left-to-right traversal).
    var sessionIds: [UUID] { layout.sessionIds }

    /// Whether this tab has a split layout (more than one session).
    var isSplit: Bool { layout.isSplit }
}
