import Foundation
import Observation

@MainActor
@Observable
final class InboxNotificationDrawerPresenter {
    private(set) var request: DrawerInboxRequest?

    func open(forDrawerPaneIds drawerPaneIds: [UUID]) {
        request = DrawerInboxRequest(id: UUID(), drawerPaneIds: drawerPaneIds)
    }

    func clearRequest(_ request: DrawerInboxRequest) {
        guard self.request == request else { return }
        self.request = nil
    }
}
