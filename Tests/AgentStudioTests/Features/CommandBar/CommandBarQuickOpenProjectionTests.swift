import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Command-T Quick Open projection", .serialized)
struct CommandBarQuickOpenProjectionTests {
    @Test("empty Quick Open projects Current rows, Recent, and remaining topology without duplicate paths")
    func emptyRootProjectsCurrentRecentAndRepositoryWorktreeRows() throws {
        try withTestAtomRegistry { atoms in
            let fixture = try makeFixture(atoms: atoms)
            atoms.applicationEntityRecency.hydrate([
                try ApplicationEntityRecency(
                    entity: .worktree(worktreeStableKey: fixture.currentLinkedWorktree.stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 300)
                ),
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: fixture.recentRepository.stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 200)
                ),
            ])

            let items = quickOpenItems(
                queryState: .empty,
                store: fixture.store,
                focus: fixture.focus
            )

            #expect(
                CommandBarDataSource.grouped(items).map(\.name)
                    == ["Current", "Recent", "Repositories & Worktrees"]
            )
            #expect(
                items.filter { $0.group == "Current" }.map(\.id)
                    == [
                        "repo-wt-\(fixture.currentLinkedWorktree.id.uuidString)",
                        "directory-\(StableKey.fromPath(fixture.watchedPath.path))",
                        "directory-\(StableKey.fromPath(FileManager.default.homeDirectoryForCurrentUser))",
                    ]
            )
            #expect(
                items.filter { $0.group == "Recent" }.map(\.id)
                    == ["repo-\(fixture.recentRepository.id.uuidString)"]
            )
            #expect(
                items.filter { $0.group == "Repositories & Worktrees" }.map(\.id)
                    == ["repo-\(fixture.remainingRepository.id.uuidString)"]
            )
            #expect(!items.contains { $0.id == "repo-wt-\(fixture.remainingMainWorktree.id.uuidString)" })
            #expect(Set(items.map(\.id)).count == items.count)
            #expect(
                items.filter { $0.id.hasPrefix("directory-") }
                    .allSatisfy { !$0.hasChildren && !$0.showsActionsButton }
            )
        }
    }

    @Test("Current uses focused pane cwd when the pane has no worktree")
    func currentUsesFocusedPaneCWDWithoutWorktree() throws {
        try withTestAtomRegistry { atoms in
            let fixture = try makeFixture(atoms: atoms)
            let cwd = URL(filePath: "/tmp/quick-open-focused-cwd")
            let pane = fixture.store.paneAtom.createPane(
                launchDirectory: cwd,
                zmxSessionID: .generateUUIDv7(),
                facets: PaneContextFacets(cwd: cwd)
            )

            let items = quickOpenItems(
                queryState: .empty,
                store: fixture.store,
                focus: WorkspacePaneFocus(
                    activePaneId: pane.id,
                    paneContentType: .terminal,
                    satisfiedRequirements: [.hasActiveTab, .hasActivePane]
                )
            )

            #expect(items.first?.id == "directory-\(StableKey.fromPath(cwd))")
            #expect(items.first?.group == "Current")
        }
    }

    @Test("Current deduplicates identical cwd, watched-root, and home paths")
    func currentDeduplicatesPaths() {
        withTestAtomRegistry { atoms in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology
            )
            let preparation = RepositoryTopologyReplacement.prepare(
                repositories: [],
                watchedPaths: [WatchedPath(path: home)],
                unavailableRepositoryIDs: []
            )
            guard case .prepared(let replacement) = preparation else {
                Issue.record("Expected valid duplicate-path topology fixture")
                return
            }
            store.repositoryTopologyAtom.replaceTopology(replacement)
            let pane = store.paneAtom.createPane(
                launchDirectory: home,
                zmxSessionID: .generateUUIDv7(),
                facets: PaneContextFacets(cwd: home)
            )

            let items = quickOpenItems(
                queryState: .empty,
                store: store,
                focus: WorkspacePaneFocus(
                    activePaneId: pane.id,
                    paneContentType: .terminal,
                    satisfiedRequirements: [.hasActiveTab, .hasActivePane]
                )
            )

            #expect(items.filter { $0.group == "Current" }.count == 1)
            #expect(items.first?.id == "directory-\(StableKey.fromPath(home))")
        }
    }

    @Test("meaningful Quick Open search uses one flat repository and worktree set")
    func meaningfulRootUsesRepositoryAndWorktreeRowsOnly() throws {
        try withTestAtomRegistry { atoms in
            let fixture = try makeFixture(atoms: atoms)
            try atoms.applicationEntityRecency.recordOpened(
                repositoryStableKey: fixture.recentRepository.stableKey,
                worktreeStableKey: fixture.currentLinkedWorktree.stableKey,
                at: Date(timeIntervalSince1970: 100)
            )

            let items = quickOpenItems(
                queryState: .meaningful,
                store: fixture.store,
                focus: fixture.focus
            )

            #expect(CommandBarDataSource.grouped(items).map(\.name) == ["Repositories & Worktrees"])
            #expect(
                Set(items.map(\.id))
                    == Set([
                        "repo-\(fixture.remainingRepository.id.uuidString)",
                        "repo-wt-\(fixture.currentLinkedWorktree.id.uuidString)",
                        "repo-\(fixture.recentRepository.id.uuidString)",
                    ])
            )
        }
    }

    private func quickOpenItems(
        queryState: CommandBarRootQueryState,
        store: WorkspaceStore,
        focus: WorkspacePaneFocus
    ) -> [CommandBarItem] {
        CommandBarDataSource.items(
            scope: .quickOpen,
            rootQueryState: queryState,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            focus: focus
        )
    }

    private func makeFixture(atoms: AtomRegistry) throws -> Fixture {
        let store = WorkspaceStore(
            identityAtom: atoms.workspaceIdentity,
            repositoryTopologyAtom: atoms.workspaceRepositoryTopology
        )

        let remainingRepositoryID = UUID()
        let remainingMainWorktree = Worktree(
            repoId: remainingRepositoryID,
            name: "main",
            path: URL(filePath: "/tmp/quick-open-remaining"),
            isMainWorktree: true
        )
        let currentLinkedWorktree = Worktree(
            repoId: remainingRepositoryID,
            name: "feature",
            path: URL(filePath: "/tmp/quick-open-remaining-feature")
        )
        let remainingRepository = Repo(
            id: remainingRepositoryID,
            name: "remaining",
            repoPath: remainingMainWorktree.path,
            worktrees: [remainingMainWorktree, currentLinkedWorktree]
        )

        let recentRepositoryID = UUID()
        let recentMainWorktree = Worktree(
            repoId: recentRepositoryID,
            name: "main",
            path: URL(filePath: "/tmp/quick-open-recent"),
            isMainWorktree: true
        )
        let recentRepository = Repo(
            id: recentRepositoryID,
            name: "recent",
            repoPath: recentMainWorktree.path,
            worktrees: [recentMainWorktree]
        )
        let watchedPath = WatchedPath(path: URL(filePath: "/tmp/quick-open-watched-root"))

        let preparation = RepositoryTopologyReplacement.prepare(
            repositories: [remainingRepository, recentRepository],
            watchedPaths: [watchedPath],
            unavailableRepositoryIDs: []
        )
        guard case .prepared(let replacement) = preparation else {
            Issue.record("Expected valid Quick Open topology fixture")
            throw FixtureError.invalidTopology
        }
        store.repositoryTopologyAtom.replaceTopology(replacement)

        return Fixture(
            store: store,
            remainingRepository: remainingRepository,
            remainingMainWorktree: remainingMainWorktree,
            currentLinkedWorktree: currentLinkedWorktree,
            recentRepository: recentRepository,
            watchedPath: watchedPath,
            focus: WorkspacePaneFocus(
                activeRepoId: remainingRepository.id,
                activeWorktreeId: currentLinkedWorktree.id,
                paneContentType: .terminal,
                satisfiedRequirements: [.hasActiveTab, .hasActivePane]
            )
        )
    }

    private struct Fixture {
        let store: WorkspaceStore
        let remainingRepository: Repo
        let remainingMainWorktree: Worktree
        let currentLinkedWorktree: Worktree
        let recentRepository: Repo
        let watchedPath: WatchedPath
        let focus: WorkspacePaneFocus
    }

    private enum FixtureError: Error {
        case invalidTopology
    }
}
