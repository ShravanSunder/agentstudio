import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBarSurfaceAtom")
struct CommandBarSurfaceAtomTests {
    @Test("surface starts inactive")
    func surfaceStartsInactive() {
        let atom = CommandBarSurfaceAtom()

        #expect(atom.activeScope == nil)
        #expect(!atom.isActive)
    }

    @Test("present updates active scope")
    func presentUpdatesActiveScope() {
        let atom = CommandBarSurfaceAtom()

        atom.present(scope: .commands)

        #expect(atom.activeScope == .commands)
        #expect(atom.isActive)
    }

    @Test("dismiss clears active scope")
    func dismissClearsActiveScope() {
        let atom = CommandBarSurfaceAtom()
        atom.present(scope: .panes)

        atom.dismiss()

        #expect(atom.activeScope == nil)
        #expect(!atom.isActive)
    }
}
