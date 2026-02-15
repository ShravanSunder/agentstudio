import Foundation

/// A tab in the workspace. Contains panes organized into arrangements.
/// Order is implicit — determined by array position in the workspace's tabs array.
struct Tab: Codable, Identifiable, Hashable {
    // Memberwise equality so TTVC detects layout/focus/arrangement changes.
    // Hash by id only (Hashable contract: equal objects must have equal hashes,
    // but equal hashes need not imply equal objects).
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    /// Display name for this tab.
    var name: String
    /// All pane IDs owned by this tab.
    var panes: [UUID]
    /// Layout arrangements for this tab. Always has at least one default arrangement.
    var arrangements: [PaneArrangement]
    /// The currently active arrangement ID.
    var activeArrangementId: UUID
    /// The focused pane within this tab. Nil only during construction.
    var activePaneId: UUID?
    /// Display-only zoom state — NOT persisted. When set, the zoomed pane fills the tab.
    var zoomedPaneId: UUID?
    /// Panes currently minimized (collapsed to a narrow bar). Transient — NOT persisted.
    var minimizedPaneIds: Set<UUID> = []

    enum CodingKeys: CodingKey {
        case id, name, panes, arrangements, activeArrangementId, activePaneId
        // zoomedPaneId, minimizedPaneIds excluded — transient, not persisted
    }

    /// Create a tab with a single pane.
    init(id: UUID = UUID(), paneId: UUID, name: String = "Tab") {
        self.id = id
        self.name = name
        self.panes = [paneId]
        let layout = Layout(paneId: paneId)
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            visiblePaneIds: [paneId]
        )
        self.arrangements = [defaultArrangement]
        self.activeArrangementId = defaultArrangement.id
        self.activePaneId = paneId
        self.zoomedPaneId = nil
    }

    /// Create a tab with an existing layout and arrangements.
    /// Precondition: `arrangements` must contain exactly one with `isDefault == true`.
    init(
        id: UUID = UUID(),
        name: String = "Tab",
        panes: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        activePaneId: UUID?,
        zoomedPaneId: UUID? = nil,
        minimizedPaneIds: Set<UUID> = []
    ) {
        assert(!arrangements.isEmpty, "Tab must have at least one arrangement")
        assert(arrangements.filter(\.isDefault).count == 1, "Tab must have exactly one default arrangement")
        self.id = id
        self.name = name
        self.panes = panes
        self.arrangements = arrangements
        self.activeArrangementId = activeArrangementId
        self.activePaneId = activePaneId
        self.zoomedPaneId = zoomedPaneId
        self.minimizedPaneIds = minimizedPaneIds
    }

    // MARK: - Derived

    /// The default arrangement. Falls back to the first arrangement if no default is marked.
    /// Invariant: every tab must have at least one arrangement with `isDefault == true`.
    var defaultArrangement: PaneArrangement {
        guard let arr = arrangements.first(where: \.isDefault) ?? arrangements.first else {
            preconditionFailure("Tab \(id) has no arrangements — invariant violated")
        }
        return arr
    }

    /// The currently active arrangement.
    var activeArrangement: PaneArrangement {
        arrangements.first { $0.id == activeArrangementId } ?? defaultArrangement
    }

    /// All pane IDs in the active arrangement's layout (left-to-right traversal).
    var paneIds: [UUID] { activeArrangement.layout.paneIds }

    /// Whether the active arrangement has a split layout (more than one pane).
    var isSplit: Bool { activeArrangement.layout.isSplit }

    /// The layout of the active arrangement (convenience accessor).
    var layout: Layout { activeArrangement.layout }

    // MARK: - Arrangement Mutation Helpers

    /// Index of the default arrangement. Falls back to index 0 if no default marked.
    var defaultArrangementIndex: Int {
        guard let idx = arrangements.firstIndex(where: \.isDefault) else {
            preconditionFailure("Tab \(id) has no default arrangement — invariant violated")
        }
        return idx
    }

    /// Index of the active arrangement.
    var activeArrangementIndex: Int {
        arrangements.firstIndex { $0.id == activeArrangementId } ?? defaultArrangementIndex
    }
}
