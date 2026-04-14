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
                activeDrawerParentPaneId: nil,
                activeDrawerPaneId: nil,
                targetPaneId: nil,
                targetTabId: tabId,
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .unmounted,
                managementMode: .inactive,
                windowState: .key,
                triggerSource: .tabClick
            )
        )

        #expect(decision.selection == .selectTab(tabId))
        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .preserveRuntimeFocus)
    }
}
