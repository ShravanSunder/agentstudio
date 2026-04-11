import Foundation
import Observation

@MainActor
@Observable
final class TabRenamePopoverState {
    var presentedTabId: UUID?

    func present(for tabId: UUID) {
        presentedTabId = tabId
    }

    func dismiss() {
        presentedTabId = nil
    }

    func isPresented(for tabId: UUID) -> Bool {
        presentedTabId == tabId
    }
}
