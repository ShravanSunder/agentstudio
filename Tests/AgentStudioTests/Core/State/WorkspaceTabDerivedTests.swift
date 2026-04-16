import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabDerivedTests {
    @Test
    func assembleTab_preservesShellAndArrangementFields() {
        let paneA = UUID()
        let paneB = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
                .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after),
            visiblePaneIds: [paneA, paneB],
            minimizedPaneIds: [paneB]
        )
        let shell = TabShell(id: UUID(), name: "Review")
        let state = TabArrangementState(
            tabId: shell.id,
            allPaneIds: [paneA, paneB],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: paneA,
            zoomedPaneId: nil
        )

        let tab = WorkspaceTabDerived.assembleTab(shell: shell, arrangementState: state)

        #expect(tab.id == shell.id)
        #expect(tab.name == "Review")
        #expect(tab.allPaneIds == [paneA, paneB])
        #expect(tab.activeArrangementId == arrangement.id)
        #expect(tab.activePaneId == paneA)
        #expect(tab.activeMinimizedPaneIds == [paneB])
    }
}
