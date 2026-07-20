import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite
struct WorkspaceArrangementCursorAtomTests {
    @Test("native cursor replacement preserves explicit empty selections")
    func nativeCursorReplacementPreservesExplicitEmptySelections() {
        let atom = WorkspaceArrangementCursorAtom()
        let tabID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let drawerKey = ArrangementDrawerCursorKey(
            arrangementId: arrangementID,
            drawerId: UUIDv7.generate()
        )

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabID: arrangementID],
            paneCursorsByArrangementId: [arrangementID: .init(activePaneId: nil)],
            drawerCursorsByKey: [drawerKey: .init(activeChildId: nil)]
        )
        #expect(atom.activeArrangementId(forTab: tabID) == arrangementID)
        #expect(atom.paneCursorsByArrangementId[arrangementID] == .init(activePaneId: nil))
        #expect(atom.drawerCursorsByKey[drawerKey] == .init(activeChildId: nil))
    }
}
