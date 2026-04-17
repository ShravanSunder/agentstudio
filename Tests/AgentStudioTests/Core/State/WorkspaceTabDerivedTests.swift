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

    @Test
    func tabs_preservesShellOrderWhenArrangementStorageOrderDiffers() {
        let firstShell = TabShell(id: UUID(), name: "One")
        let secondShell = TabShell(id: UUID(), name: "Two")
        let firstState = TabArrangementState(
            tabId: firstShell.id,
            allPaneIds: [UUID()],
            arrangements: [PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: UUID()))],
            activeArrangementId: UUID(),
            activePaneId: nil,
            zoomedPaneId: nil
        )
        let secondState = TabArrangementState(
            tabId: secondShell.id,
            allPaneIds: [UUID()],
            arrangements: [PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: UUID()))],
            activeArrangementId: UUID(),
            activePaneId: nil,
            zoomedPaneId: nil
        )

        let shellAtom = WorkspaceTabShellAtom()
        shellAtom.appendTabShell(firstShell)
        shellAtom.appendTabShell(secondShell)
        let arrangementAtom = WorkspaceTabArrangementAtom()
        arrangementAtom.appendState(secondState)
        arrangementAtom.appendState(firstState)

        let derived = WorkspaceTabDerived(shellAtom: shellAtom, arrangementAtom: arrangementAtom)

        #expect(derived.tabs.map(\.id) == [firstShell.id, secondShell.id])
    }

    @Test
    func activeTab_returnsNilWhenActiveTabIdIsNil() {
        let shellAtom = WorkspaceTabShellAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom()

        let derived = WorkspaceTabDerived(shellAtom: shellAtom, arrangementAtom: arrangementAtom)

        #expect(derived.activeTab == nil)
    }

    @Test
    func tabContaining_returnsTabForPaneInNonActiveTab() {
        let paneA = UUID()
        let paneB = UUID()
        let firstShell = TabShell(id: UUID(), name: "One")
        let secondShell = TabShell(id: UUID(), name: "Two")
        let firstArrangement = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneA))
        let secondArrangement = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneB))

        let shellAtom = WorkspaceTabShellAtom()
        shellAtom.appendTabShell(firstShell)
        shellAtom.appendTabShell(secondShell)
        shellAtom.setActiveTab(firstShell.id)

        let arrangementAtom = WorkspaceTabArrangementAtom()
        arrangementAtom.appendState(
            TabArrangementState(
                tabId: firstShell.id,
                allPaneIds: [paneA],
                arrangements: [firstArrangement],
                activeArrangementId: firstArrangement.id,
                activePaneId: paneA,
                zoomedPaneId: nil
            )
        )
        arrangementAtom.appendState(
            TabArrangementState(
                tabId: secondShell.id,
                allPaneIds: [paneB],
                arrangements: [secondArrangement],
                activeArrangementId: secondArrangement.id,
                activePaneId: paneB,
                zoomedPaneId: nil
            )
        )

        let derived = WorkspaceTabDerived(shellAtom: shellAtom, arrangementAtom: arrangementAtom)

        #expect(derived.tabContaining(paneId: paneB)?.id == secondShell.id)
    }

    @Test
    func allPaneIds_unionsAcrossTabs() {
        let paneA = UUID()
        let paneB = UUID()
        let shellAtom = WorkspaceTabShellAtom()
        let arrangementAtom = WorkspaceTabArrangementAtom()

        let shellA = TabShell(id: UUID(), name: "One")
        let shellB = TabShell(id: UUID(), name: "Two")
        shellAtom.appendTabShell(shellA)
        shellAtom.appendTabShell(shellB)

        let arrangementA = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneA))
        let arrangementB = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneB))
        arrangementAtom.appendState(
            TabArrangementState(
                tabId: shellA.id,
                allPaneIds: [paneA],
                arrangements: [arrangementA],
                activeArrangementId: arrangementA.id,
                activePaneId: paneA,
                zoomedPaneId: nil
            )
        )
        arrangementAtom.appendState(
            TabArrangementState(
                tabId: shellB.id,
                allPaneIds: [paneB],
                arrangements: [arrangementB],
                activeArrangementId: arrangementB.id,
                activePaneId: paneB,
                zoomedPaneId: nil
            )
        )

        let derived = WorkspaceTabDerived(shellAtom: shellAtom, arrangementAtom: arrangementAtom)

        #expect(derived.allPaneIds == Set([paneA, paneB]))
    }
}
