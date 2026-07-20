import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceTabCursorAtom {
    var activeTabId: UUID? { storedActiveTabId }

    private var storedActiveTabId: UUID?

    init(activeTabId: UUID? = nil) {
        storedActiveTabId = activeTabId
    }

    func replaceActiveTab(_ activeTabId: UUID?) {
        storedActiveTabId = activeTabId
    }

    func selectTab(_ tabId: UUID?, availableTabIds: [UUID]) {
        guard let tabId else {
            storedActiveTabId = nil
            return
        }
        guard availableTabIds.contains(tabId) else { return }
        storedActiveTabId = tabId
    }

    func removeTab(_ tabId: UUID, remainingTabIds: [UUID]) {
        guard storedActiveTabId == tabId else { return }
        storedActiveTabId = remainingTabIds.last
    }
}
