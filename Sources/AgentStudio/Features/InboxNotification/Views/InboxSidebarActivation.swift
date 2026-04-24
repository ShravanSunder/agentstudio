import Foundation

enum InboxSidebarActivationOutcome: Equatable {
    case focusPane(UUID)
    case flashRow(UUID)
}

enum InboxSidebarActivationResolver {
    @MainActor
    static func resolve(
        notification: InboxNotification,
        workspacePaneAtom: WorkspacePaneAtom
    ) -> InboxSidebarActivationOutcome {
        guard
            let paneId = notification.paneId,
            workspacePaneAtom.pane(paneId) != nil
        else {
            return .flashRow(notification.id)
        }

        return .focusPane(paneId)
    }
}
