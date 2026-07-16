import Foundation
import Testing

@testable import AgentStudio

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
