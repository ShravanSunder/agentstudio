import Foundation

/// A child pane within a Drawer. Holds any content type and inherits context from its parent Pane.
/// DrawerPanes cannot have their own drawers — nesting is prevented by construction (no `drawer` field).
struct DrawerPane: Codable, Identifiable, Hashable {
    let id: UUID
    /// Content displayed in this drawer pane.
    var content: PaneContent
    /// Metadata for context tracking. Inherits parent pane's source/cwd at creation.
    var metadata: PaneMetadata

    init(
        id: UUID = UUID(),
        content: PaneContent,
        metadata: PaneMetadata
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
    }
}
