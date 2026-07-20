import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace tab owner indexes")
struct WorkspaceTabOwnerIndexTests {
    @Test("Tab shell count and membership follow every structural mutation route")
    func tabShellCountAndMembershipFollowStructuralMutations() {
        // Arrange
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUIDv7.generate(), name: "First")
        let second = TabShell(id: UUIDv7.generate(), name: "Second")
        let replacement = TabShell(id: UUIDv7.generate(), name: "Replacement")

        // Act and assert
        atom.replaceTabShells([first])
        #expect(atom.tabCount == 1)
        #expect(atom.containsTab(first.id))
        #expect(!atom.containsTab(second.id))

        atom.insertTabShell(second, at: 0)
        #expect(atom.tabCount == 2)
        #expect(atom.containsTab(first.id))
        #expect(atom.containsTab(second.id))

        atom.removeTabShell(first.id)
        #expect(atom.tabCount == 1)
        #expect(!atom.containsTab(first.id))
        #expect(atom.containsTab(second.id))

        atom.replaceTabShells([replacement])
        #expect(atom.tabCount == 1)
        #expect(!atom.containsTab(second.id))
        #expect(atom.containsTab(replacement.id))
    }

    @Test("Tab graph replacement rebuilds count, membership, pane, and arrangement indexes")
    func tabGraphReplacementRebuildsMaintainedIndexes() {
        // Arrange
        let atom = WorkspaceTabGraphAtom()
        let first = makeTabGraphState()
        let second = makeTabGraphState()
        let replacement = makeTabGraphState()

        // Act and assert
        atom.replaceTabStates([first, second])
        #expect(atom.tabCount == 2)
        #expect(atom.containsTab(first.tabId))
        #expect(atom.containsTab(second.tabId))
        #expect(atom.tabID(containingPane: first.allPaneIds[0]) == first.tabId)
        #expect(atom.tabID(containingArrangement: first.arrangements[0].id) == first.tabId)
        #expect(atom.tabID(containingArrangement: second.arrangements[1].id) == second.tabId)

        atom.replaceTabStates([replacement])
        #expect(atom.tabCount == 1)
        #expect(!atom.containsTab(first.tabId))
        #expect(!atom.containsTab(second.tabId))
        #expect(atom.containsTab(replacement.tabId))
        #expect(atom.tabID(containingPane: first.allPaneIds[0]) == nil)
        #expect(atom.tabID(containingArrangement: first.arrangements[0].id) == nil)
        #expect(atom.tabID(containingArrangement: replacement.arrangements[0].id) == replacement.tabId)
    }

    @Test("Pane graph drawer owner index follows replacement, overwrite, and removal")
    func paneGraphDrawerOwnerIndexFollowsStructuralMutations() throws {
        // Arrange
        let atom = WorkspacePaneGraphAtom()
        let firstParent = makePane()
        let secondParent = makePane()
        let firstState = PaneGraphState(pane: firstParent)
        let secondState = PaneGraphState(pane: secondParent)
        let firstDrawerID = try #require(firstState.drawer?.drawerId)
        let secondDrawerID = try #require(secondState.drawer?.drawerId)
        atom.replacePaneStates(try requirePaneGraphReplacement([firstState.id: firstState]))

        // Act and assert
        #expect(atom.parentPaneID(containingDrawer: firstDrawerID) == firstState.id)
        #expect(atom.parentPaneID(containingDrawer: secondDrawerID) == nil)

        atom.setCanonicalPaneState(secondState)
        #expect(atom.parentPaneID(containingDrawer: firstDrawerID) == firstState.id)
        #expect(atom.parentPaneID(containingDrawer: secondDrawerID) == secondState.id)

        var firstStateWithReplacementDrawer = firstState
        firstStateWithReplacementDrawer.kind = .layout(drawer: DrawerGraphState(parentPaneId: firstState.id))
        let replacementDrawerID = try #require(firstStateWithReplacementDrawer.drawer?.drawerId)
        atom.setCanonicalPaneState(firstStateWithReplacementDrawer)
        #expect(atom.parentPaneID(containingDrawer: firstDrawerID) == nil)
        #expect(atom.parentPaneID(containingDrawer: replacementDrawerID) == firstState.id)
        #expect(atom.parentPaneID(containingDrawer: secondDrawerID) == secondState.id)

        atom.removeCanonicalPaneState(for: secondState.id)
        #expect(atom.parentPaneID(containingDrawer: secondDrawerID) == nil)
    }
}

private func makeTabGraphState() -> TabGraphState {
    let firstPaneID = UUIDv7.generate()
    let secondPaneID = UUIDv7.generate()
    return TabGraphState(
        tabId: UUIDv7.generate(),
        allPaneIds: [firstPaneID, secondPaneID],
        arrangements: [
            PaneArrangementGraphState(
                id: UUIDv7.generate(),
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: firstPaneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: false,
                drawerViews: [:]
            ),
            PaneArrangementGraphState(
                id: UUIDv7.generate(),
                name: "Review",
                isDefault: false,
                layout: Layout(paneId: secondPaneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: true,
                drawerViews: [:]
            ),
        ]
    )
}

private func makePane() -> Pane {
    Pane(
        content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
        metadata: PaneMetadata()
    )
}

private func requirePaneGraphReplacement(
    _ paneStates: [UUID: PaneGraphState]
) throws -> WorkspacePaneGraphReplacement {
    switch WorkspacePaneGraphReplacement.prepare(paneStates) {
    case .success(let replacement):
        replacement
    case .failure(let rejection):
        throw WorkspaceTabOwnerIndexTestError.replacementRejected(rejection)
    }
}

private enum WorkspaceTabOwnerIndexTestError: Error {
    case replacementRejected(WorkspacePaneGraphReplacementRejection)
}
