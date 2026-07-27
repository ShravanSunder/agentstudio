import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneTabClickFocusDeciderTests {
    @Test("tab click selects tab without implicit responder move")
    func tabClick_selectsTab_withoutImplicitResponderMove() {
        let tabId = UUID()

        let decision = PaneTabClickFocusDecider.decide(
            trigger: PaneTabClickFocusTrigger(targetTabId: tabId),
            context: PaneFocusContext(
                activeTabId: nil,
                activePaneId: nil,
                activeDrawer: nil,
                targetPaneId: nil,
                targetTabId: tabId,
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .unmounted,
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.selection == .selectTab(tabId))
        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .preserveRuntimeFocus)
    }
}
