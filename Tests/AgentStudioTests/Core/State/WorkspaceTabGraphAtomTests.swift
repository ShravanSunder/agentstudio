import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite
struct WorkspaceTabGraphAtomTests {
    @Test("last graph lookup uses the maintained ID index")
    func lastGraphLookupUsesMaintainedIndex() {
        // Arrange
        let atom = WorkspaceTabGraphAtom()
        let states = (0..<300).map { _ in makeGraphState() }
        atom.replaceStates(states)

        // Act
        let lastState = atom.tabState(states[299].tabId)

        // Assert
        #expect(lastState == states[299])
        #expect(atom.tabIndex(for: states[299].tabId) == 299)
    }

    @Test("keyed graph lookup ignores unrelated tab insertion")
    func keyedGraphLookupIgnoresUnrelatedTabInsertion() {
        // Arrange
        let atom = WorkspaceTabGraphAtom()
        let observedState = makeGraphState()
        let unrelatedState = makeGraphState()
        atom.replaceStates([observedState])
        let invalidation = WorkspaceTabGraphObservationCounter()
        withObservationTracking {
            _ = atom.tabState(observedState.tabId)
        } onChange: {
            invalidation.record()
        }

        // Act
        atom.replaceStates([observedState, unrelatedState])

        // Assert
        #expect(!invalidation.didFire)
        #expect(atom.tabState(observedState.tabId) == observedState)
        #expect(atom.tabState(unrelatedState.tabId) == unrelatedState)
    }

    @Test("keyed graph revision changes only for the selected tab")
    func keyedGraphRevisionChangesOnlyForSelectedTab() {
        let observedState = makeGraphState()
        let unrelatedState = makeGraphState()
        let atom = WorkspaceTabGraphAtom()
        atom.replaceStates([observedState])
        let initialRevision = atom.tabStateRevision(for: observedState.tabId)

        atom.replaceStates([observedState, unrelatedState])
        #expect(atom.tabStateRevision(for: observedState.tabId) == initialRevision)

        var changedState = observedState
        changedState.allPaneIds.append(UUIDv7.generate())
        atom.replaceStates([changedState, unrelatedState])

        #expect(atom.tabStateRevision(for: observedState.tabId) != initialRevision)
    }

}

private final class WorkspaceTabGraphObservationCounter: @unchecked Sendable {
    private(set) var didFire = false

    func record() {
        didFire = true
    }
}

private func makeGraphState() -> TabGraphState {
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
                drawerViews: [:]
            ),
            PaneArrangementGraphState(
                id: UUIDv7.generate(),
                name: "Review",
                isDefault: false,
                layout: Layout(paneId: secondPaneID),
                minimizedPaneIds: [],
                drawerViews: [:]
            ),
        ]
    )
}
