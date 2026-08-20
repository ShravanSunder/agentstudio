import AgentStudioCore
import AgentStudioInfrastructure
import CoreTransferable
import Foundation
import SwiftUI

/// Preview view shown by SwiftUI's `.draggable(_:preview:)` when a drag session actually begins.
struct DragHandleDragPreview: View {
    let paneId: UUID
    let drawerParentPaneId: UUID?
    let tabId: UUID

    init(paneId: UUID, drawerParentPaneId: UUID?, tabId: UUID) {
        self.paneId = paneId
        self.drawerParentPaneId = drawerParentPaneId
        self.tabId = tabId
        RestoreTrace.log(
            "DragHandleDragPreview.init pane=\(paneId) drawerParent=\(drawerParentPaneId?.uuidString ?? "nil") tab=\(tabId)"
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppStyles.Shell.ManagementLayer.dragHandleCornerRadius)
                .fill(Color(.windowBackgroundColor).opacity(0.8))
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: AppStyles.General.Icon.toolbar, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(
            width: AppStyles.Shell.ManagementLayer.dragHandleWidth,
            height: AppStyles.Shell.ManagementLayer.dragHandleHeight
        )
        .onAppear {
            let sessionID = DragSession.start()
            let source = drawerParentPaneId == nil ? "main-pane" : "drawer-pane"
            RestoreTrace.log(
                "DragHandleDragPreview.onAppear session=\(sessionID) source=\(source) pane=\(paneId) drawerParent=\(drawerParentPaneId?.uuidString ?? "nil") tab=\(tabId)"
            )
        }
        .onDisappear {
            RestoreTrace.log(
                "DragHandleDragPreview.onDisappear pane=\(paneId) drawerParent=\(drawerParentPaneId?.uuidString ?? "nil") tab=\(tabId)"
            )
        }
    }
}

/// Payload for dragging the new tab button.
struct NewTabDragPayload: Codable, Transferable {
    var timestamp = Date()

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioNewTab)
    }
}
