import Foundation

/// Per-arrangement view state for a non-empty drawer.
struct DrawerView: Codable, Hashable {
    /// Spatial arrangement of panes within the drawer's local grid.
    var layout: DrawerGridLayout
    /// Currently focused pane in the drawer. Nil only when empty.
    var activeChildId: UUID?
    /// Panes currently minimized to narrow vertical bars.
    var minimizedPaneIds: Set<UUID>
    /// Whether minimized drawer panes are still rendered as collapsed bars.
    var showsMinimizedPanes: Bool

    init(
        layout: DrawerGridLayout = DrawerGridLayout(),
        activeChildId: UUID? = nil,
        minimizedPaneIds: Set<UUID> = [],
        showsMinimizedPanes: Bool = true
    ) {
        self.layout = layout
        self.activeChildId = Self.normalizedActiveChildId(activeChildId, paneIds: layout.paneIds)
        self.minimizedPaneIds = minimizedPaneIds.intersection(layout.paneIds)
        self.showsMinimizedPanes = showsMinimizedPanes
    }

    private static func normalizedActiveChildId(_ activeChildId: UUID?, paneIds: [UUID]) -> UUID? {
        guard !paneIds.isEmpty else { return nil }
        guard let activeChildId, paneIds.contains(activeChildId) else { return paneIds[0] }
        return activeChildId
    }
}

/// A named complete view of panes within a Tab.
/// Each tab has exactly one default arrangement and zero or more custom arrangements.
struct PaneArrangement: Codable, Identifiable, Hashable {
    let id: UUID
    /// Display name for this arrangement.
    var name: String
    /// Whether this is the default arrangement (exactly one per tab).
    var isDefault: Bool
    /// The spatial layout of panes in this arrangement.
    var layout: Layout
    /// Pane IDs currently minimized in this arrangement.
    var minimizedPaneIds: Set<UUID>
    /// Whether minimized panes are still rendered as collapsed bars.
    var showsMinimizedPanes: Bool
    /// Focused pane for this arrangement. Nil only when the arrangement has no visible candidate.
    var activePaneId: UUID?
    /// Per-arrangement drawer view state, keyed by `Drawer.drawerId`.
    var drawerViews: [UUID: DrawerView]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDefault
        case layout
        case minimizedPaneIds
        case showsMinimizedPanes
        case activePaneId
        case drawerViews
    }

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isDefault: Bool = true,
        layout: Layout,
        minimizedPaneIds: Set<UUID> = [],
        showsMinimizedPanes: Bool = true,
        activePaneId: UUID? = nil,
        drawerViews: [UUID: DrawerView] = [:]
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.layout = layout
        self.minimizedPaneIds = minimizedPaneIds.intersection(layout.paneIds)
        self.showsMinimizedPanes = showsMinimizedPanes
        self.activePaneId = Self.normalizedActivePaneId(
            activePaneId, layout: layout, minimizedPaneIds: minimizedPaneIds)
        self.drawerViews = drawerViews
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        layout = try container.decode(Layout.self, forKey: .layout)
        minimizedPaneIds =
            try container.decode(Set<UUID>.self, forKey: .minimizedPaneIds)
            .intersection(layout.paneIds)
        showsMinimizedPanes = try container.decode(Bool.self, forKey: .showsMinimizedPanes)
        activePaneId = Self.normalizedActivePaneId(
            try container.decodeIfPresent(UUID.self, forKey: .activePaneId),
            layout: layout,
            minimizedPaneIds: minimizedPaneIds
        )
        drawerViews = try container.decode([UUID: DrawerView].self, forKey: .drawerViews)
    }

    private static func normalizedActivePaneId(
        _ activePaneId: UUID?,
        layout: Layout,
        minimizedPaneIds: Set<UUID>
    ) -> UUID? {
        guard !layout.isEmpty else { return nil }
        if let activePaneId, layout.contains(activePaneId), !minimizedPaneIds.contains(activePaneId) {
            return activePaneId
        }
        return layout.paneIds.first { !minimizedPaneIds.contains($0) } ?? layout.paneIds.first
    }
}
