import Foundation

enum InboxSidebarActivationOutcome: Equatable {
    case focusPane(UUID)
    case flashRow(UUID)
    case openFullDiskAccessSettings
}

enum InboxSidebarActivationResolver {
    @MainActor
    static func resolve(
        notification: InboxNotification,
        workspacePaneAtom: WorkspacePaneAtom
    ) -> InboxSidebarActivationOutcome {
        if notification.kind == .fullDiskAccessDenied {
            return .openFullDiskAccessSettings
        }
        guard
            let paneId = notification.paneId,
            workspacePaneAtom.pane(paneId) != nil
        else {
            return .flashRow(notification.id)
        }

        return .focusPane(paneId)
    }
}
