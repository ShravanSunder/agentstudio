import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct WorkspaceRichTabSnapshotTests {
    @Test("tab shell revision advances only for accepted semantic changes")
    func tabShellRevisionTracksAcceptedChanges() throws {
        let shell = TabShell(id: UUID(), name: "One")
        let atom = WorkspaceTabShellAtom()

        #expect(atom.tabShellRevision == 0)

        atom.appendTabShell(shell)
        #expect(atom.tabShellRevision == 1)

        atom.appendTabShell(shell)
        #expect(atom.tabShellRevision == 1)

        atom.renameTab(shell.id, name: "Renamed")
        #expect(atom.tabShellRevision == 2)

        atom.renameTab(shell.id, name: "Renamed")
        #expect(atom.tabShellRevision == 2)

        try atom.setTabColorHex("#AABBCC", tabId: shell.id)
        #expect(atom.tabShellRevision == 3)

        try atom.setTabColorHex("#aabbcc", tabId: shell.id)
        #expect(atom.tabShellRevision == 3)
    }

    @Test("tab graph revision advances only when graph content changes")
    func tabGraphRevisionTracksAcceptedChanges() {
        let state = TabGraphState(
            tabId: UUID(),
            allPaneIds: [UUID()],
            arrangements: []
        )
        let atom = WorkspaceTabGraphAtom()

        #expect(atom.tabGraphRevision == 0)

        atom.replaceStates([state])
        #expect(atom.tabGraphRevision == 1)

        atom.replaceStates([state])
        #expect(atom.tabGraphRevision == 1)

        atom.replaceStates([])
        #expect(atom.tabGraphRevision == 2)
    }

    @Test("each arrangement cursor collection has an independent semantic revision")
    func arrangementCursorRevisionsTrackIndependentCollections() {
        let tabId = UUID()
        let firstArrangementId = UUID()
        let secondArrangementId = UUID()
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let drawerId = UUID()
        let firstDrawerPaneId = UUID()
        let secondDrawerPaneId = UUID()
        let atom = WorkspaceArrangementCursorAtom()

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: firstArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: firstPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: firstDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 1)
        #expect(atom.activePaneRevision == 1)
        #expect(atom.drawerChildRevision == 1)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: firstPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: firstDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 1)
        #expect(atom.drawerChildRevision == 1)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: secondPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: firstDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 2)
        #expect(atom.drawerChildRevision == 1)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: secondPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: secondDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 2)
        #expect(atom.drawerChildRevision == 2)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: secondPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: secondDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 2)
        #expect(atom.drawerChildRevision == 2)
    }

    @Test("rich snapshot preserves shell order and invalidates after compound replacement")
    func richSnapshotMatchesCanonicalAssemblyAfterCompoundReplacement() {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let firstTab = Tab(paneId: firstPaneId, name: "First")
        let secondTab = Tab(paneId: secondPaneId, name: "Second")
        let atom = WorkspaceTabLayoutAtom()

        atom.replaceTabs(
            [secondTab, firstTab],
            activeTabId: firstTab.id,
            validPaneIds: [firstPaneId, secondPaneId]
        )

        let firstSnapshot = atom.richTabSnapshot
        let directFirstAssembly = WorkspaceTabLayoutDerived(
            shellAtom: atom.shellAtom,
            arrangementAtom: atom.arrangementAtom
        ).tabs
        #expect(firstSnapshot.orderedTabs == directFirstAssembly)
        #expect(firstSnapshot.orderedTabs.map(\.id) == [secondTab.id, firstTab.id])

        let renamedFirstTab = Tab(
            id: firstTab.id,
            name: "First Renamed",
            allPaneIds: firstTab.allPaneIds,
            arrangements: firstTab.arrangements,
            activeArrangementId: firstTab.activeArrangementId
        )
        atom.replaceTabs(
            [renamedFirstTab],
            activeTabId: renamedFirstTab.id,
            validPaneIds: [firstPaneId]
        )

        let secondSnapshot = atom.richTabSnapshot
        let directSecondAssembly = WorkspaceTabLayoutDerived(
            shellAtom: atom.shellAtom,
            arrangementAtom: atom.arrangementAtom
        ).tabs
        #expect(secondSnapshot.orderedTabs == directSecondAssembly)
        #expect(secondSnapshot.orderedTabs.map(\.name) == ["First Renamed"])
    }
}
