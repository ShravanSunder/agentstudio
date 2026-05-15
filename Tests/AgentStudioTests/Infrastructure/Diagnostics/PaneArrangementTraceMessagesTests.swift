import Foundation
import Testing

@testable import AgentStudio

@Suite("Pane arrangement trace messages")
struct PaneArrangementTraceMessagesTests {
    @Test
    func crossTabPaneMoveTraceIncludesTabCloseOutcome() {
        let paneId = UUID()
        let sourceTabId = UUID()
        let destTabId = UUID()

        let message = PaneArrangementTraceMessages.crossTabPaneMove(
            paneId: paneId,
            sourceTabId: sourceTabId,
            destTabId: destTabId,
            sourceTabClosed: true
        )

        #expect(message.contains("movePaneAcrossTabs"))
        #expect(message.contains("pane=\(paneId)"))
        #expect(message.contains("sourceTab=\(sourceTabId)"))
        #expect(message.contains("destTab=\(destTabId)"))
        #expect(message.contains("sourceClosed=true"))
    }
}
