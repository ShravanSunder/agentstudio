import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceNavigationScopeAtomTests {
    @Test("empty drawer focus is first-class")
    func emptyDrawerFocus_isFirstClass() {
        let atom = WorkspaceNavigationScopeAtom()
        let parentPaneId = UUID()

        atom.focusEmptyDrawer(parentPaneId: parentPaneId)

        #expect(atom.scope == .emptyDrawer(parentPaneId: parentPaneId))
    }
}
