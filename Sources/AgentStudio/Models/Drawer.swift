import Foundation

/// A collapsible panel below a Pane, holding DrawerPanes.
/// Drawers inherit context from their parent Pane.
struct Drawer: Codable, Hashable {
    /// The drawer panes in display order.
    var panes: [DrawerPane]
    /// Currently active drawer pane. Nil only when panes is empty.
    var activeDrawerPaneId: UUID?
    /// Whether the drawer is expanded (visible) or collapsed.
    var isExpanded: Bool

    init(
        panes: [DrawerPane] = [],
        activeDrawerPaneId: UUID? = nil,
        isExpanded: Bool = true
    ) {
        self.panes = panes
        self.activeDrawerPaneId = activeDrawerPaneId
        self.isExpanded = isExpanded
    }
}
