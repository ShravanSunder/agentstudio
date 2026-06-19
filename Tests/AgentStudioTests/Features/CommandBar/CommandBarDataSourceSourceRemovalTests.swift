import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBar source removal", .serialized)
struct CommandBarDataSourceSourceRemovalTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func everythingScopeRoamedFloatingPaneClassifiesFromLiveFacets() throws {
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/command-bar-roamed-floating"))
        let worktree = try #require(repo.worktrees.first)
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        _ = store.paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: worktree.path,
            resolvedContext: (repo: repo, worktree: worktree)
        )

        let items = CommandBarDataSource.items(
            scope: .everything,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: AppCommandDispatcher.shared
        )
        let paneItem = items.first { $0.id == "pane-\(pane.id.uuidString)" }

        guard case .dispatchTargeted(let command, let target, let targetType) = paneItem?.action else {
            Issue.record("Expected pane item to dispatch a targeted focus command")
            return
        }

        #expect(command == .focusPane)
        #expect(target == pane.id)
        #expect(targetType == .pane)
    }
}
