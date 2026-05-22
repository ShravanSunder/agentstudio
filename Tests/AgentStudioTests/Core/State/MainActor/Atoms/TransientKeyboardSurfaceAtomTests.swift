import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TransientKeyboardSurfaceAtom")
struct TransientKeyboardSurfaceAtomTests {
    @Test("surfaces are exposed as a token-scoped stack")
    func surfacesAreTokenScopedStack() {
        let atom = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()

        let firstToken = atom.present(.tabRename(tabId: firstTabId), workspaceWindowId: workspaceWindowId)
        let secondToken = atom.present(.tabRename(tabId: secondTabId), workspaceWindowId: workspaceWindowId)

        #expect(atom.surfaces.map(\.token) == [firstToken, secondToken])
        #expect(atom.topAnySurface?.kind == .tabRename(tabId: secondTabId))
        #expect(atom.topSurface(for: workspaceWindowId)?.kind == .tabRename(tabId: secondTabId))

        atom.dismiss(firstToken)

        #expect(atom.surfaces.map(\.token) == [secondToken])
        #expect(atom.topSurface(for: workspaceWindowId)?.kind == .tabRename(tabId: secondTabId))

        atom.dismiss(secondToken)

        #expect(atom.surfaces.isEmpty)
        #expect(atom.topAnySurface == nil)
    }

    @Test("window scoped lookup ignores transients from other workspace windows")
    func windowScopedLookupIgnoresOtherWorkspaceWindows() {
        let atom = TransientKeyboardSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()

        _ = atom.present(.tabRename(tabId: firstTabId), workspaceWindowId: firstWindowId)
        _ = atom.present(.tabRename(tabId: secondTabId), workspaceWindowId: secondWindowId)

        #expect(atom.topAnySurface?.kind == .tabRename(tabId: secondTabId))
        #expect(atom.topSurface(for: firstWindowId)?.kind == .tabRename(tabId: firstTabId))
        #expect(atom.topSurface(for: UUID()) == nil)
    }
}
