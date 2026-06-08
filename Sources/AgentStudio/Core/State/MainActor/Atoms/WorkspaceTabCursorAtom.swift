import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceTabCursorAtom {
    private(set) var activeTabId: UUID?

    func hydrate(activeTabId: UUID?, availableTabIds: [UUID]) {
        if let activeTabId, availableTabIds.contains(activeTabId) {
            self.activeTabId = activeTabId
        } else {
            self.activeTabId = availableTabIds.first
        }
    }

    func selectTab(_ tabId: UUID?, availableTabIds: [UUID]) {
        guard let tabId else {
            activeTabId = nil
            return
        }
        guard availableTabIds.contains(tabId) else { return }
        activeTabId = tabId
    }

    func removeTab(_ tabId: UUID, remainingTabIds: [UUID]) {
        guard activeTabId == tabId else { return }
        activeTabId = remainingTabIds.last
    }
}
