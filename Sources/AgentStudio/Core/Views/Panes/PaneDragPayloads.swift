import AgentStudioInfrastructure
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Payload for dragging an existing tab.
package struct TabDragPayload: Codable, Transferable {
    package let tabId: UUID

    package init(tabId: UUID) {
        self.tabId = tabId
    }

    package static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioTab)
    }
}

/// Payload for dragging an individual pane.
package struct PaneDragPayload: Codable, Transferable {
    package let paneId: UUID
    package let tabId: UUID
    package let drawerParentPaneId: UUID?

    package init(paneId: UUID, tabId: UUID, drawerParentPaneId: UUID? = nil) {
        self.paneId = paneId
        self.tabId = tabId
        self.drawerParentPaneId = drawerParentPaneId
    }

    package static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioPane)
    }
}
