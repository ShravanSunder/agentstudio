import Foundation

enum DragLatchResetDecision {
    static func shouldResetLatch(
        currentLatchedPaneId: UUID?,
        previousActiveTabId: UUID,
        newActiveTabId: UUID
    ) -> Bool {
        guard currentLatchedPaneId != nil else { return false }
        return previousActiveTabId != newActiveTabId
    }
}
