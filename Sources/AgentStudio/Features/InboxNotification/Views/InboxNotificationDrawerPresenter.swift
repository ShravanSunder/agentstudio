import Foundation
import Observation

/// Presentation bridge for opening a drawer-scoped notification popover from
/// command routing without making AppDelegate own SwiftUI popover state.
@MainActor
@Observable
final class InboxNotificationDrawerPresenter {
    struct Request: Equatable, Identifiable {
        let id: UUID
        let drawerPaneIds: [UUID]
    }

    private(set) var request: Request?

    func open(forDrawerPaneIds drawerPaneIds: [UUID]) {
        request = Request(id: UUID(), drawerPaneIds: drawerPaneIds)
    }

    func clearRequest(_ request: Request) {
        guard self.request == request else { return }
        self.request = nil
    }
}
