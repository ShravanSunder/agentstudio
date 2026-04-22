import Foundation

/// A container holding child panes in a layout, attached to a parent layout pane.
/// Mirrors Tab's container capabilities: layout splits, minimize, focus tracking.
struct Drawer: Codable, Hashable {
    /// Pane IDs owned by this drawer, in insertion order.
    var paneIds: [UUID]
    /// Spatial arrangement of panes within the drawer's local grid.
    var layout: DrawerGridLayout
    /// Currently focused pane in the drawer. Nil only when empty.
    var activePaneId: UUID?
    /// Whether the drawer panel is expanded (visible) or collapsed.
    var isExpanded: Bool
    /// Panes currently minimized to narrow vertical bars. Transient — not persisted.
    var minimizedPaneIds: Set<UUID>

    init(
        paneIds: [UUID] = [],
        layout: DrawerGridLayout = DrawerGridLayout(),
        activePaneId: UUID? = nil,
        isExpanded: Bool = false,
        minimizedPaneIds: Set<UUID> = []
    ) {
        self.paneIds = paneIds
        self.layout = layout
        self.activePaneId = activePaneId
        self.isExpanded = isExpanded
        self.minimizedPaneIds = minimizedPaneIds
    }

    enum CodingKeys: CodingKey {
        case paneIds, layout, activePaneId, isExpanded
        // minimizedPaneIds excluded — transient, not persisted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paneIds = try container.decode([UUID].self, forKey: .paneIds)

        // Backward-compat: persisted workspaces from before the drawer-grid
        // rework stored `layout` as a single flat `Layout`. Current format is
        // `DrawerGridLayout` (one or optional two rows). Try the current
        // format first; on failure, decode as legacy `Layout` and wrap into a
        // one-row grid. Without this, old workspace files silently fail to
        // decode and the workspace is treated as corrupt → empty-state
        // restore (user-visible data loss on upgrade).
        if let gridLayout = try? container.decode(DrawerGridLayout.self, forKey: .layout) {
            layout = gridLayout
        } else {
            let legacyLayout = try container.decode(Layout.self, forKey: .layout)
            layout = DrawerGridLayout(topRow: legacyLayout, bottomRow: nil, rowSplitRatio: 0.5)
        }

        activePaneId = try container.decodeIfPresent(UUID.self, forKey: .activePaneId)
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
        minimizedPaneIds = []  // transient — always starts empty on decode
    }
}
