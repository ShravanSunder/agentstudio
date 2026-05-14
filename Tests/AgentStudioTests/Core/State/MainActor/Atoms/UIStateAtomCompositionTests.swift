import Testing

@testable import AgentStudio

@MainActor
@Suite("UIStateAtom composition state")
struct UIStateAtomCompositionTests {
    @Test("sidebarCollapsed defaults to false")
    func sidebarCollapsedDefault() {
        let atom = UIStateAtom()
        #expect(atom.sidebarCollapsed == false)
    }

    @Test("setSidebarCollapsed updates value")
    func setSidebarCollapsed() {
        let atom = UIStateAtom()
        atom.setSidebarCollapsed(true)
        #expect(atom.sidebarCollapsed == true)

        atom.setSidebarCollapsed(false)
        #expect(atom.sidebarCollapsed == false)
    }

    @Test("sidebarSurface defaults to repos")
    func sidebarSurfaceDefault() {
        let atom = UIStateAtom()
        #expect(atom.sidebarSurface == .repos)
    }

    @Test("setSidebarSurface updates value")
    func setSidebarSurface() {
        let atom = UIStateAtom()
        atom.setSidebarSurface(.inbox)
        #expect(atom.sidebarSurface == .inbox)

        atom.setSidebarSurface(.repos)
        #expect(atom.sidebarSurface == .repos)
    }

    @Test("sidebarHasFocus defaults to false")
    func sidebarHasFocusDefault() {
        let atom = UIStateAtom()
        #expect(atom.sidebarHasFocus == false)
    }

    @Test("setSidebarHasFocus updates value")
    func setSidebarHasFocus() {
        let atom = UIStateAtom()
        atom.setSidebarHasFocus(true)
        #expect(atom.sidebarHasFocus == true)

        atom.setSidebarHasFocus(false)
        #expect(atom.sidebarHasFocus == false)
    }
}
