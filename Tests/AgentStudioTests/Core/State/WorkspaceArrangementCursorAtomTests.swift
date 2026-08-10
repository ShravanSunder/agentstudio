import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

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

    @Test("keyed cursor lookups ignore unrelated tab insertion")
    func keyedCursorLookupsIgnoreUnrelatedTabInsertion() {
        // Arrange
        let atom = WorkspaceArrangementCursorAtom()
        let observedTabID = UUIDv7.generate()
        let observedArrangementID = UUIDv7.generate()
        let observedDrawerKey = ArrangementDrawerCursorKey(
            arrangementId: observedArrangementID,
            drawerId: UUIDv7.generate()
        )
        let observedPaneID = UUIDv7.generate()
        let observedDrawerChildID = UUIDv7.generate()
        atom.replaceCursors(
            activeArrangementIdsByTabId: [observedTabID: observedArrangementID],
            paneCursorsByArrangementId: [observedArrangementID: .init(activePaneId: observedPaneID)],
            drawerCursorsByKey: [observedDrawerKey: .init(activeChildId: observedDrawerChildID)]
        )
        let invalidation = WorkspaceArrangementCursorObservationCounter()
        withObservationTracking {
            _ = atom.activeArrangementId(forTab: observedTabID)
            _ = atom.activePaneId(forArrangement: observedArrangementID)
            _ = atom.activeChildId(
                forArrangement: observedDrawerKey.arrangementId,
                drawerId: observedDrawerKey.drawerId
            )
        } onChange: {
            invalidation.record()
        }

        let unrelatedTabID = UUIDv7.generate()
        let unrelatedArrangementID = UUIDv7.generate()
        let unrelatedDrawerKey = ArrangementDrawerCursorKey(
            arrangementId: unrelatedArrangementID,
            drawerId: UUIDv7.generate()
        )

        // Act
        atom.replaceCursors(
            activeArrangementIdsByTabId: [
                observedTabID: observedArrangementID,
                unrelatedTabID: unrelatedArrangementID,
            ],
            paneCursorsByArrangementId: [
                observedArrangementID: .init(activePaneId: observedPaneID),
                unrelatedArrangementID: .init(activePaneId: UUIDv7.generate()),
            ],
            drawerCursorsByKey: [
                observedDrawerKey: .init(activeChildId: observedDrawerChildID),
                unrelatedDrawerKey: .init(activeChildId: UUIDv7.generate()),
            ]
        )

        // Assert
        #expect(!invalidation.didFire)
        #expect(atom.activeArrangementId(forTab: observedTabID) == observedArrangementID)
        #expect(atom.activePaneId(forArrangement: observedArrangementID) == observedPaneID)
        #expect(
            atom.activeChildId(
                forArrangement: observedDrawerKey.arrangementId,
                drawerId: observedDrawerKey.drawerId
            ) == observedDrawerChildID
        )
    }
}

private final class WorkspaceArrangementCursorObservationCounter: @unchecked Sendable {
    private(set) var didFire = false

    func record() {
        didFire = true
    }
}
