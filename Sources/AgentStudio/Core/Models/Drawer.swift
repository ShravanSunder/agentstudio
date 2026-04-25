import Foundation

/// A container holding child panes in a layout, attached to a parent layout pane.
/// Mirrors Tab's container capabilities: layout splits, minimize, focus tracking.
struct Drawer: Codable, Hashable {
    /// Pane IDs owned by this drawer, in insertion order.
    var paneIds: [UUID]
    /// Spatial arrangement of panes (same Layout type as Tab uses).
    var layout: Layout
    /// Currently focused pane in the drawer. Nil only when empty.
    var activeChildId: UUID?
    /// Whether the drawer panel is expanded (visible) or collapsed.
    var isExpanded: Bool
    /// Panes currently minimized to narrow vertical bars. Transient — not persisted.
    var minimizedPaneIds: Set<UUID>

    init(
        paneIds: [UUID] = [],
        layout: Layout = Layout(),
        activeChildId: UUID? = nil,
        isExpanded: Bool = false,
        minimizedPaneIds: Set<UUID> = []
    ) {
        self.paneIds = paneIds
        self.layout = layout
        self.activeChildId = Self.normalizedActiveChildId(activeChildId, paneIds: paneIds)
        self.isExpanded = isExpanded
        self.minimizedPaneIds = minimizedPaneIds
    }

    enum CodingKeys: CodingKey {
        case paneIds, layout, activeChildId, activePaneId, isExpanded
        // minimizedPaneIds excluded — transient, not persisted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paneIds = try container.decode([UUID].self, forKey: .paneIds)
        layout = try container.decode(Layout.self, forKey: .layout)
        if container.contains(.activePaneId), !container.contains(.activeChildId) {
            throw DecodingError.dataCorruptedError(
                forKey: .activePaneId,
                in: container,
                debugDescription: "Drawer activePaneId is unsupported; expected activeChildId"
            )
        }
        activeChildId = Self.normalizedActiveChildId(
            try container.decodeIfPresent(UUID.self, forKey: .activeChildId),
            paneIds: paneIds
        )
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
        minimizedPaneIds = []  // transient — always starts empty on decode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paneIds, forKey: .paneIds)
        try container.encode(layout, forKey: .layout)
        try container.encodeIfPresent(activeChildId, forKey: .activeChildId)
        try container.encode(isExpanded, forKey: .isExpanded)
    }

    private static func normalizedActiveChildId(_ activeChildId: UUID?, paneIds: [UUID]) -> UUID? {
        guard !paneIds.isEmpty else { return nil }
        guard let activeChildId, paneIds.contains(activeChildId) else { return paneIds[0] }
        return activeChildId
    }
}
