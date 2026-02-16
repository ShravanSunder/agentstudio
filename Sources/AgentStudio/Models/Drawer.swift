import Foundation

/// A container holding child panes in a layout, attached to a parent layout pane.
/// Mirrors Tab's container capabilities: layout splits, minimize, focus tracking.
struct Drawer: Codable, Hashable {
    /// Pane IDs owned by this drawer, in insertion order.
    var paneIds: [UUID]
    /// Spatial arrangement of panes (same Layout type as Tab uses).
    var layout: Layout
    /// Currently focused pane in the drawer. Nil only when empty.
    var activePaneId: UUID?
    /// Whether the drawer panel is expanded (visible) or collapsed.
    var isExpanded: Bool
    /// Panes currently minimized to narrow vertical bars. Transient — not persisted.
    var minimizedPaneIds: Set<UUID>

    init(
        paneIds: [UUID] = [],
        layout: Layout = Layout(),
        activePaneId: UUID? = nil,
        isExpanded: Bool = true,
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
        layout = try container.decode(Layout.self, forKey: .layout)
        activePaneId = try container.decodeIfPresent(UUID.self, forKey: .activePaneId)
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
        minimizedPaneIds = [] // transient — always starts empty on decode
    }
}
