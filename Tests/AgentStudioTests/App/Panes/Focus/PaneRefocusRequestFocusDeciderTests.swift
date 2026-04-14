import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneRefocusRequestFocusDeciderTests {
    @Test("refocus request for unmounted pane falls back to pane host focus")
    func refocusUnmountedPane_fallsBackToPaneHost() {
        let paneId = UUID()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .explicit),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneId,
                activeDrawerParentPaneId: nil,
                activeDrawerPaneId: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .webview,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .unmounted,
                managementMode: .inactive,
                windowState: .key,
                triggerSource: .refocusRequest
            )
        )

        #expect(decision.responder == .focusPaneHost(paneId: paneId))
    }
}
