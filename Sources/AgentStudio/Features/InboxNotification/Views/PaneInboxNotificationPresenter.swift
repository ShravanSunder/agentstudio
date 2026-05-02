import Foundation
import Observation

@MainActor
@Observable
final class PaneInboxNotificationPresenter {
    private(set) var request: PaneInboxRequest?
    private var presentedTarget: PaneInboxTarget?

    func open(parentPaneId: UUID, paneIds: [UUID]) {
        request = PaneInboxRequest(id: UUID(), parentPaneId: parentPaneId, paneIds: paneIds, intent: .open)
    }

    func toggle(parentPaneId: UUID, paneIds: [UUID]) {
        let target = PaneInboxTarget(parentPaneId: parentPaneId, paneIds: paneIds)
        if presentedTarget == target {
            request = PaneInboxRequest(id: UUID(), parentPaneId: parentPaneId, paneIds: paneIds, intent: .close)
            return
        }

        if request?.target == target, request?.intent == .open {
            request = nil
            return
        }

        open(parentPaneId: parentPaneId, paneIds: paneIds)
    }

    func setPresented(parentPaneId: UUID, paneIds: [UUID], isPresented: Bool) {
        let target = PaneInboxTarget(parentPaneId: parentPaneId, paneIds: paneIds)
        if isPresented {
            presentedTarget = target
        } else if presentedTarget == target {
            presentedTarget = nil
        }
    }

    func clearRequest(_ request: PaneInboxRequest) {
        guard self.request == request else { return }
        self.request = nil
    }
}

private struct PaneInboxTarget: Equatable {
    let parentPaneId: UUID
    let paneIds: [UUID]
}

extension PaneInboxRequest {
    fileprivate var target: PaneInboxTarget {
        PaneInboxTarget(parentPaneId: parentPaneId, paneIds: paneIds)
    }
}
