import Foundation
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
        let workspaceWindowId = UUID()

        atom.present(scope: .commands, workspaceWindowId: workspaceWindowId)

        #expect(atom.activeScope == .commands)
        #expect(atom.activeScope(for: workspaceWindowId) == .commands)
        #expect(atom.isActive)
    }

    @Test("active scope is window scoped")
    func activeScopeIsWindowScoped() {
        let atom = CommandBarSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()

        atom.present(scope: .commands, workspaceWindowId: firstWindowId)

        #expect(atom.activeScope(for: firstWindowId) == .commands)
        #expect(atom.activeScope(for: secondWindowId) == nil)
    }

    @Test("present moves active scope to new window")
    func presentMovesActiveScopeToNewWindow() {
        let atom = CommandBarSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()

        atom.present(scope: .commands, workspaceWindowId: firstWindowId)
        atom.present(scope: .panes, workspaceWindowId: secondWindowId)

        #expect(atom.activeScope(for: firstWindowId) == nil)
        #expect(atom.activeScope(for: secondWindowId) == .panes)
        #expect(atom.activeScope == .panes)
    }

    @Test("dismiss clears active scope")
    func dismissClearsActiveScope() {
        let atom = CommandBarSurfaceAtom()
        let workspaceWindowId = UUID()
        atom.present(scope: .panes, workspaceWindowId: workspaceWindowId)

        atom.dismiss(workspaceWindowId: workspaceWindowId)

        #expect(atom.activeScope == nil)
        #expect(!atom.isActive)
    }

    @Test("dismiss ignores other windows")
    func dismissIgnoresOtherWindows() {
        let atom = CommandBarSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        atom.present(scope: .repos, workspaceWindowId: firstWindowId)

        atom.dismiss(workspaceWindowId: secondWindowId)

        #expect(atom.activeScope(for: firstWindowId) == .repos)
        #expect(atom.isActive)
    }
}
