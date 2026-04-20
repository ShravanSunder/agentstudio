import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarSurfaceHost")
struct SidebarSurfaceHostTests {
    @Test("repos surface maps to repo explorer child")
    func childKindRepos() {
        let uiState = UIStateAtom()
        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .repoExplorer)
    }

    @Test("inbox surface maps to placeholder child")
    func childKindInbox() {
        let uiState = UIStateAtom()
        uiState.setSidebarSurface(.inbox)

        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .inboxPlaceholder)
    }
}
