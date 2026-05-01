import Foundation
import Observation

@MainActor
@Observable
final class PaneInboxNotificationPresenter {
    private(set) var request: PaneInboxRequest?

    func open(parentPaneId: UUID, paneIds: [UUID]) {
        request = PaneInboxRequest(id: UUID(), parentPaneId: parentPaneId, paneIds: paneIds)
    }

    func toggle(parentPaneId: UUID, paneIds: [UUID]) {
        if request?.parentPaneId == parentPaneId,
            request?.paneIds == paneIds
        {
            request = nil
            return
        }

        open(parentPaneId: parentPaneId, paneIds: paneIds)
    }

    func clearRequest(_ request: PaneInboxRequest) {
        guard self.request == request else { return }
        self.request = nil
    }
}
