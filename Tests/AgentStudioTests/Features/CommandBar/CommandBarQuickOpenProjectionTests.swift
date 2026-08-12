import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCommandBar
@testable import AgentStudioCore

@MainActor
@Suite("Command-T Quick Open projection", .serialized)
struct CommandBarQuickOpenProjectionTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("empty Quick Open projects Current rows, Recent, and remaining topology without duplicate paths")
    func emptyRootProjectsCurrentRecentAndRepositoryWorktreeRows() throws {
        try withTestCoreAtoms { coreAtoms in
            let fixture = try makeFixture(coreAtoms: coreAtoms)
            coreAtoms.applicationEntityRecency.hydrate([
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
                focusedPane: fixture.focusedPane
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
        try withTestCoreAtoms { coreAtoms in
            let fixture = try makeFixture(coreAtoms: coreAtoms)
            let cwd = URL(filePath: "/tmp/quick-open-focused-cwd")
            let pane = fixture.store.paneAtom.createPane(
                launchDirectory: cwd,
                zmxSessionID: .generateUUIDv7(),
                facets: PaneContextFacets(cwd: cwd)
            )

            let items = quickOpenItems(
                queryState: .empty,
                store: fixture.store,
                focusedPane: makeFocusedPane(
                    paneID: pane.id
                )
            )

            #expect(items.first?.id == "directory-\(StableKey.fromPath(cwd))")
            #expect(items.first?.group == "Current")
        }
    }

    @Test("Current deduplicates identical cwd, watched-root, and home paths")
    func currentDeduplicatesPaths() {
        withTestCoreAtoms { coreAtoms in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let store = WorkspaceStore(
                identityAtom: coreAtoms.workspaceIdentity,
                repositoryTopologyAtom: coreAtoms.workspaceRepositoryTopology
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
                focusedPane: makeFocusedPane(
                    paneID: pane.id
                )
            )

            #expect(items.filter { $0.group == "Current" }.count == 1)
            #expect(items.first?.id == "directory-\(StableKey.fromPath(home))")
        }
    }

    @Test("Current preserves worktree activation when a watched root matches its path")
    func watchedRootMatchingWorktreePreservesWorktreeActivation() throws {
        try withTestCoreAtoms { coreAtoms in
            let store = WorkspaceStore(
                identityAtom: coreAtoms.workspaceIdentity,
                repositoryTopologyAtom: coreAtoms.workspaceRepositoryTopology
            )
            let repositoryID = UUIDv7.generate()
            let mainWorktree = Worktree(
                repoId: repositoryID,
                name: "main",
                path: URL(filePath: "/tmp/quick-open-watched-repository"),
                isMainWorktree: true
            )
            let linkedWorktree = Worktree(
                repoId: repositoryID,
                name: "feature",
                path: URL(filePath: "/tmp/quick-open-watched-repository-feature")
            )
            let repository = Repo(
                id: repositoryID,
                name: "watched-repository",
                repoPath: mainWorktree.path,
                worktrees: [mainWorktree, linkedWorktree]
            )
            let preparation = RepositoryTopologyReplacement.prepare(
                repositories: [repository],
                watchedPaths: [WatchedPath(path: linkedWorktree.path)],
                unavailableRepositoryIDs: []
            )
            guard case .prepared(let replacement) = preparation else {
                Issue.record("Expected valid watched-worktree topology fixture")
                return
            }
            store.repositoryTopologyAtom.replaceTopology(replacement)

            let items = quickOpenItems(
                queryState: .empty,
                store: store,
                focusedPane: nil
            )

            let currentWorktreeItem = try #require(
                items.first { $0.group == "Current" && $0.id == "repo-wt-\(linkedWorktree.id.uuidString)" }
            )
            guard
                case .quickOpen(.worktree(let projectedStableKey)) = currentWorktreeItem.action
            else {
                Issue.record("Expected the Current row to preserve worktree activation")
                return
            }
            #expect(projectedStableKey == linkedWorktree.stableKey)
            #expect(
                !items.contains {
                    $0.id == "directory-\(StableKey.fromPath(linkedWorktree.path))"
                }
            )
        }
    }

    @Test("meaningful Quick Open search uses one flat repository and worktree set")
    func meaningfulRootUsesRepositoryAndWorktreeRowsOnly() throws {
        try withTestCoreAtoms { coreAtoms in
            let fixture = try makeFixture(coreAtoms: coreAtoms)
            try coreAtoms.applicationEntityRecency.recordOpened(
                repositoryStableKey: fixture.recentRepository.stableKey,
                worktreeStableKey: fixture.currentLinkedWorktree.stableKey,
                at: Date(timeIntervalSince1970: 100)
            )

            let items = quickOpenItems(
                queryState: .meaningful,
                store: fixture.store,
                focusedPane: fixture.focusedPane
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
        focusedPane: WorkspaceFocusedPane?
    ) -> [CommandBarItem] {
        CommandBarDataSource.items(
            scope: .quickOpen,
            rootQueryState: queryState,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher(),
            focusedPane: focusedPane,
            commandContext: .empty
        )
    }

    private func makeFocusedPane(
        paneID: UUID = UUID(),
        repoID: UUID? = nil,
        worktreeID: UUID? = nil
    ) -> WorkspaceFocusedPane {
        WorkspaceFocusedPane(
            owner: .mainPane(paneId: paneID),
            activeMainPaneId: paneID,
            paneId: paneID,
            repoId: repoID,
            worktreeId: worktreeID,
            contentType: .terminal
        )
    }

    private func makeFixture(coreAtoms: CoreAtoms) throws -> Fixture {
        let store = WorkspaceStore(
            identityAtom: coreAtoms.workspaceIdentity,
            repositoryTopologyAtom: coreAtoms.workspaceRepositoryTopology
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
            focusedPane: makeFocusedPane(
                repoID: remainingRepository.id,
                worktreeID: currentLinkedWorktree.id
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
        let focusedPane: WorkspaceFocusedPane
    }

    private enum FixtureError: Error {
        case invalidTopology
    }
}
