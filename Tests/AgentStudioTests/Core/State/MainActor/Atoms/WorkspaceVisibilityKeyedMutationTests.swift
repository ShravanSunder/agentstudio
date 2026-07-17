import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace visibility keyed atom mutations")
struct WorkspaceVisibilityKeyedMutationTests {
    @Test("tab graph keyed replacement preserves unrelated values and owner indexes")
    func tabGraphReplacementPreservesIndexes() {
        // Arrange
        let fixture = makeVisibilityFixture()
        let unrelated = makeTabGraphLeafFixture().tabState
        let atom = WorkspaceTabGraphAtom()
        atom.replaceTabStates([fixture.context.tabStates[0], unrelated])
        var replacement = fixture.context.tabStates[0]
        replacement.arrangements[0].showsMinimizedPanes = false

        // Act
        atom.replaceTabStatePreservingIdentity(replacement)

        // Assert
        #expect(atom.tabStates == [replacement, unrelated])
        #expect(atom.tabIndex(for: fixture.tabID) == 0)
        #expect(atom.tabIndex(for: unrelated.tabId) == 1)
        for paneID in fixture.paneIDs {
            #expect(atom.tabID(containingPane: paneID) == fixture.tabID)
        }
        for arrangement in replacement.arrangements {
            #expect(atom.tabID(containingArrangement: arrangement.id) == fixture.tabID)
        }
    }

    @Test("cursor keyed setters preserve unrelated cursor families")
    func cursorSettersPreserveUnrelatedKeys() {
        // Arrange
        let fixture = makeVisibilityFixture()
        let atom = WorkspaceArrangementCursorAtom()
        let unrelatedTabID = UUIDv7.generate()
        let unrelatedArrangementID = UUIDv7.generate()
        let drawerKey = ArrangementDrawerCursorKey(
            arrangementId: unrelatedArrangementID,
            drawerId: UUIDv7.generate()
        )
        let drawerChildID = UUIDv7.generate()
        atom.replaceCursors(
            activeArrangementIdsByTabId: [
                fixture.tabID: fixture.defaultArrangementID,
                unrelatedTabID: unrelatedArrangementID,
            ],
            paneCursorsByArrangementId: [
                fixture.defaultArrangementID: .init(activePaneId: fixture.paneIDs[0]),
                unrelatedArrangementID: .init(activePaneId: drawerChildID),
            ],
            drawerCursorsByKey: [drawerKey: .init(activeChildId: drawerChildID)]
        )

        // Act
        atom.setActiveArrangementId(fixture.customArrangementID, forTab: fixture.tabID)
        atom.setPaneCursor(
            .init(activePaneId: fixture.paneIDs[1]),
            forArrangement: fixture.defaultArrangementID
        )

        // Assert
        #expect(atom.activeArrangementId(forTab: fixture.tabID) == fixture.customArrangementID)
        #expect(atom.activePaneId(forArrangement: fixture.defaultArrangementID) == fixture.paneIDs[1])
        #expect(atom.activeArrangementId(forTab: unrelatedTabID) == unrelatedArrangementID)
        #expect(atom.activePaneId(forArrangement: unrelatedArrangementID) == drawerChildID)
        #expect(
            atom.activeChildId(forArrangement: unrelatedArrangementID, drawerId: drawerKey.drawerId) == drawerChildID)
    }
}
