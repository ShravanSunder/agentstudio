import Foundation
import Observation

@MainActor
@Observable
final class InboxNotificationDrawerPresenter {
    private(set) var request: DrawerInboxRequest?

    func open(parentPaneId: UUID, drawerPaneIds: [UUID]) {
        request = DrawerInboxRequest(id: UUID(), parentPaneId: parentPaneId, drawerPaneIds: drawerPaneIds)
    }

    func clearRequest(_ request: DrawerInboxRequest) {
        guard self.request == request else { return }
        self.request = nil
    }
}
