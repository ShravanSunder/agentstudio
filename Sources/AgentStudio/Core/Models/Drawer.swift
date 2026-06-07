import Foundation

/// A drawer container attached to a parent layout pane.
/// View state such as layout, focus, and minimized panes lives on `PaneArrangement`.
struct Drawer: Codable, Hashable {
    let drawerId: UUID
    let parentPaneId: UUID
    /// Pane IDs owned by this drawer, in insertion order.
    var paneIds: [UUID]
    /// Whether the drawer panel is expanded (visible) or collapsed.
    var isExpanded: Bool

    init(
        drawerId: UUID = UUID(),
        parentPaneId: UUID,
        paneIds: [UUID] = [],
        isExpanded: Bool = false
    ) {
        self.drawerId = drawerId
        self.parentPaneId = parentPaneId
        self.paneIds = paneIds
        self.isExpanded = isExpanded
    }

    enum CodingKeys: String, CodingKey {
        case drawerId, parentPaneId, paneIds, isExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drawerId = try container.decode(UUID.self, forKey: .drawerId)
        parentPaneId = try container.decode(UUID.self, forKey: .parentPaneId)
        paneIds = try container.decode([UUID].self, forKey: .paneIds)
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(drawerId, forKey: .drawerId)
        try container.encode(parentPaneId, forKey: .parentPaneId)
        try container.encode(paneIds, forKey: .paneIds)
        try container.encode(isExpanded, forKey: .isExpanded)
    }
}
