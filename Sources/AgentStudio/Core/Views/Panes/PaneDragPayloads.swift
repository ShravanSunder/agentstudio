import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Payload for dragging an existing tab.
struct TabDragPayload: Codable, Transferable {
    let tabId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioTab)
    }
}

/// Payload for dragging an individual pane.
struct PaneDragPayload: Codable, Transferable {
    let paneId: UUID
    let tabId: UUID
    let drawerParentPaneId: UUID?

    init(paneId: UUID, tabId: UUID, drawerParentPaneId: UUID? = nil) {
        self.paneId = paneId
        self.tabId = tabId
        self.drawerParentPaneId = drawerParentPaneId
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioPane)
    }
}
