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

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isDefault: Bool = true,
        layout: Layout,
        visiblePaneIds: Set<UUID>? = nil
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.layout = layout
        self.visiblePaneIds = visiblePaneIds ?? Set(layout.paneIds)
    }
}
