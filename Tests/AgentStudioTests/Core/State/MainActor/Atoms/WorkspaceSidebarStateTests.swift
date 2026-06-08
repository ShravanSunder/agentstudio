import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace sidebar atoms")
struct WorkspaceSidebarStateTests {
    @Test("sidebar memory owns persisted shell fields")
    func sidebarMemoryOwnsPersistedShellFields() {
        let atom = WorkspaceSidebarMemoryAtom()

        #expect(atom.filterText.isEmpty)
        #expect(atom.isFilterVisible == false)
        #expect(atom.sidebarCollapsed == false)
        #expect(atom.sidebarSurface == .repos)

        atom.setFilterText("repo")
        atom.setFilterVisible(true)
        atom.setSidebarCollapsed(true)
        atom.setSidebarSurface(.inbox)

        #expect(atom.filterText == "repo")
        #expect(atom.isFilterVisible == true)
        #expect(atom.sidebarCollapsed == true)
        #expect(atom.sidebarSurface == .inbox)
    }

    @Test("sidebar focus runtime owns focus only")
    func sidebarFocusRuntimeOwnsFocusOnly() {
        let atom = SidebarFocusRuntimeAtom()

        #expect(atom.sidebarHasFocus == false)

        atom.setSidebarHasFocus(true)
        #expect(atom.sidebarHasFocus == true)

        atom.clear()
        #expect(atom.sidebarHasFocus == false)
    }

    @Test("workspace sidebar state composes memory and focus without owning fields")
    func workspaceSidebarStateComposesSplitOwners() {
        let memory = WorkspaceSidebarMemoryAtom()
        let focus = SidebarFocusRuntimeAtom()
        let state = WorkspaceSidebarState(memoryAtom: memory, focusAtom: focus)

        state.setFilterText("terminal")
        state.setFilterVisible(true)
        state.setSidebarCollapsed(true)
        state.setSidebarSurface(.inbox)
        state.setSidebarHasFocus(true)

        #expect(memory.filterText == "terminal")
        #expect(memory.isFilterVisible == true)
        #expect(memory.sidebarCollapsed == true)
        #expect(memory.sidebarSurface == .inbox)
        #expect(focus.sidebarHasFocus == true)

        state.clear()

        #expect(memory.filterText.isEmpty)
        #expect(memory.isFilterVisible == false)
        #expect(memory.sidebarCollapsed == false)
        #expect(memory.sidebarSurface == .repos)
        #expect(focus.sidebarHasFocus == false)
    }
}
