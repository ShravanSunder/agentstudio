import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("SidebarSurfaceHost", .serialized)
struct SidebarSurfaceHostTests {
    @Test("Repo Explorer is the only sidebar child")
    func repoExplorerIsOnlySidebarChild() {
        let uiState = WorkspaceSidebarState()

        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .repoExplorer)
    }

    @Test("legacy Inbox selection normalizes to Repo Explorer")
    func legacyInboxSelectionNormalizesToRepoExplorer() {
        let uiState = WorkspaceSidebarState()

        uiState.setSidebarSurface(.inbox)

        #expect(uiState.sidebarSurface == .repos)
        #expect(SidebarSurfaceHost.currentChildKind(uiState: uiState) == .repoExplorer)
    }
}
