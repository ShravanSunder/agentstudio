import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DragLatchResetDecisionTests {
    private let tabA = UUID()
    private let tabB = UUID()
    private let paneId = UUID()

    @Test
    func reset_whenTabChanges_andLatchPresent() {
        #expect(
            DragLatchResetDecision.shouldResetLatch(
                currentLatchedPaneId: paneId,
                previousActiveTabId: tabA,
                newActiveTabId: tabB
            )
        )
    }

    @Test
    func noReset_whenTabUnchanged() {
        #expect(
            !DragLatchResetDecision.shouldResetLatch(
                currentLatchedPaneId: paneId,
                previousActiveTabId: tabA,
                newActiveTabId: tabA
            )
        )
    }

    @Test
    func noReset_whenNoLatchPresent() {
        #expect(
            !DragLatchResetDecision.shouldResetLatch(
                currentLatchedPaneId: nil,
                previousActiveTabId: tabA,
                newActiveTabId: tabB
            )
        )
    }
}
