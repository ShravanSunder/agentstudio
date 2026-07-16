import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceDrawerCursorAtom")
struct WorkspaceDrawerCursorAtomTests {
    @Test("replacement stores one expanded drawer or no expanded drawer")
    func replacementStoresOneExpandedDrawerOrNoExpandedDrawer() {
        let atom = WorkspaceDrawerCursorAtom()
        let firstDrawerID = UUID()
        let secondDrawerID = UUID()

        atom.replaceExpandedDrawer(firstDrawerID)
        #expect(atom.expandedDrawerId == firstDrawerID)

        atom.replaceExpandedDrawer(secondDrawerID)
        #expect(atom.expandedDrawerId == secondDrawerID)

        atom.replaceExpandedDrawer(nil)
        #expect(atom.expandedDrawerId == nil)
    }
}
