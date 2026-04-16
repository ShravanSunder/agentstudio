import Foundation

/// A named arrangement of panes within a Tab.
/// Each tab has exactly one default arrangement (contains all panes) and zero or more custom arrangements.
struct PaneArrangement: Codable, Identifiable, Hashable {
    let id: UUID
    /// Display name for this arrangement.
    var name: String
    /// Whether this is the default arrangement (exactly one per tab).
    var isDefault: Bool
    /// The spatial layout of panes in this arrangement.
    var layout: Layout
    /// Which pane IDs are visible in this arrangement (subset of tab's panes for custom, all for default).
    var visiblePaneIds: Set<UUID>
    /// Which visible pane IDs are currently minimized in this arrangement.
    var minimizedPaneIds: Set<UUID>

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDefault
        case layout
        case visiblePaneIds
        case minimizedPaneIds
    }

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isDefault: Bool = true,
        layout: Layout,
        visiblePaneIds: Set<UUID>? = nil,
        minimizedPaneIds: Set<UUID> = []
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.layout = layout
        self.visiblePaneIds = visiblePaneIds ?? Set(layout.paneIds)
        self.minimizedPaneIds = minimizedPaneIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        layout = try container.decode(Layout.self, forKey: .layout)
        visiblePaneIds =
            try container.decodeIfPresent(Set<UUID>.self, forKey: .visiblePaneIds)
            ?? Set(layout.paneIds)
        minimizedPaneIds =
            try container.decodeIfPresent(Set<UUID>.self, forKey: .minimizedPaneIds)
            ?? []
    }
}
