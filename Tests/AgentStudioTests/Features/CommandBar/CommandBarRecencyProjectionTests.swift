import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Command Bar recency projection", .serialized)
struct CommandBarRecencyProjectionTests {
    @Test("empty roots project typed recency while meaningful roots retain each canonical row once")
    func emptyAndMeaningfulRootsHaveExactProjectionBoundaries() throws {
        try withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology
            )
            let recentRepo = store.addRepo(at: URL(filePath: "/tmp/recency-projection-recent"))
            let remainingRepo = store.addRepo(at: URL(filePath: "/tmp/recency-projection-remaining"))
            let recentWorktree = try #require(store.repositoryTopologyAtom.repo(recentRepo.id)?.worktrees.first)

            let currentPane = store.createPane(title: "Current")
            let recentPane = store.createPane(title: "Recent")
            let currentTab = Tab(paneId: currentPane.id, name: "Current Tab")
            let recentTab = Tab(paneId: recentPane.id, name: "Recent Tab")
            store.appendTab(currentTab)
            store.appendTab(recentTab)
            store.setActiveTab(currentTab.id)
            store.setActivePane(currentPane.id, inTab: currentTab.id)

            try atoms.applicationEntityRecency.recordOpened(
                repositoryStableKey: recentRepo.stableKey,
                worktreeStableKey: recentWorktree.stableKey,
                at: Date(timeIntervalSince1970: 200)
            )
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.identityAtom.workspaceId,
                recentEntities: [
                    try WorkspaceEntityRecency(
                        workspaceID: store.identityAtom.workspaceId,
                        entity: .pane(paneID: recentPane.id),
                        interaction: .focused,
                        lastInteractedAt: Date(timeIntervalSince1970: 200)
                    )
                ]
            )

            let emptyMain = items(
                scope: .everything,
                queryState: .empty,
                recentCommands: [.closeTab],
                store: store
            )
            let emptyRepos = items(
                scope: .repos,
                queryState: .empty,
                recentCommands: [.closeTab],
                store: store
            )
            let emptyPanes = items(
                scope: .panes,
                queryState: .empty,
                recentCommands: [.closeTab],
                store: store
            )
            let emptyCommands = items(
                scope: .commands,
                queryState: .empty,
                recentCommands: [.closeTab],
                store: store
            )

            #expect(groupNames(emptyMain) == ["Recent Repositories", "Repos", "Panes", "Tabs", "Commands"])
            #expect(groupNames(emptyRepos) == ["Recent Repositories", "Recent Worktrees", "Repositories"])
            #expect(groupNames(emptyPanes).first == "Recent Panes")
            #expect(groupNames(emptyCommands).first == "Recent Commands")
            #expect(emptyPanes.first { $0.group == "Recent Panes" }?.id == "pane-\(recentPane.id.uuidString)")
            #expect(emptyCommands.first { $0.group == "Recent Commands" }?.id == "cmd-\(AppCommand.closeTab.rawValue)")
            for rootItems in [emptyMain, emptyRepos, emptyPanes, emptyCommands] {
                let priorities = CommandBarDataSource.grouped(rootItems).map(\.priority)
                #expect(Set(priorities).count == priorities.count)
            }

            let recentCommand = try #require(
                emptyCommands.first { $0.group == "Recent Commands" && $0.command == .closeTab }
            )
            let canonicalCommands = items(
                scope: .commands,
                queryState: .meaningful,
                recentCommands: [.closeTab],
                store: store
            )
            let canonicalCommand = try #require(
                canonicalCommands.first { $0.command == .closeTab }
            )
            #expect(recentCommand.id == canonicalCommand.id)
            #expect(recentCommand.hasChildren)
            guard
                case .navigate(let recentLevel) = recentCommand.action,
                case .navigate(let canonicalLevel) = canonicalCommand.action
            else {
                Issue.record("Expected recent targeted command to retain canonical drill-in")
                return
            }
            #expect(recentLevel.id == canonicalLevel.id)

            assertMeaningfulRootsRetainCanonicalRows(
                store: store,
                recentRepositoryID: recentRepo.id,
                remainingRepositoryID: remainingRepo.id
            )
        }
    }

    @Test("empty recent groups are omitted from every root")
    func emptyRecentGroupsAreOmitted() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology
            )
            _ = store.addRepo(at: URL(filePath: "/tmp/recency-no-history"))

            for scope in [CommandBarScope.everything, .repos, .panes, .commands] {
                let projected = items(
                    scope: scope,
                    queryState: .empty,
                    recentCommands: [],
                    store: store
                )
                #expect(!CommandBarDataSource.grouped(projected).contains { $0.name.hasPrefix("Recent") })
            }
        }
    }

    @Test("recent pane eligibility excludes the attended pane before applying the cap")
    func recentPaneEligibilityPrecedesVisibleCap() throws {
        try withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology
            )
            var panes: [Pane] = []
            for index in 0..<7 {
                let pane = store.createPane(title: "Pane \(index)")
                let tab = Tab(paneId: pane.id, name: "Tab \(index)")
                store.appendTab(tab)
                panes.append(pane)
                if index == 0 {
                    store.setActiveTab(tab.id)
                    store.setActivePane(pane.id, inTab: tab.id)
                }
            }
            let attendedTab = try #require(store.tabLayoutAtom.tabContaining(paneId: panes[0].id))
            store.setActiveTab(attendedTab.id)
            store.setActivePane(panes[0].id, inTab: attendedTab.id)
            let workspaceID = store.identityAtom.workspaceId
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: workspaceID,
                recentEntities: try panes.enumerated().map { index, pane in
                    try WorkspaceEntityRecency(
                        workspaceID: workspaceID,
                        entity: .pane(paneID: pane.id),
                        interaction: .focused,
                        lastInteractedAt: Date(timeIntervalSince1970: Double(100 - index))
                    )
                }
            )

            let projected = items(
                scope: .panes,
                queryState: .empty,
                recentCommands: [],
                store: store
            )
            let recentPaneIDs =
                projected
                .filter { $0.group == "Recent Panes" }
                .map(\.id)

            #expect(recentPaneIDs.count == 5)
            #expect(!recentPaneIDs.contains("pane-\(panes[0].id.uuidString)"))
            #expect(
                recentPaneIDs
                    == panes[1...5].map { "pane-\($0.id.uuidString)" }
            )
        }
    }

    @Test("recent repository rows enter menus and repositories without a live worktree omit")
    func recentRepositoryProjectionProducesMenuRows() throws {
        try withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology
            )
            let launchableRepo = store.addRepo(at: URL(filePath: "/tmp/recency-direct-repo"))
            let launchableWorktree = try #require(
                store.repositoryTopologyAtom.repo(launchableRepo.id)?.worktrees.first
            )
            let staleRepo = store.addRepo(at: URL(filePath: "/tmp/recency-no-worktree"))
            store.reconcileDiscoveredWorktrees(staleRepo.id, worktrees: [])

            atoms.applicationEntityRecency.hydrate([
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: staleRepo.stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 300)
                ),
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: launchableRepo.stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 200)
                ),
            ])
            atoms.applicationEntityRecency.record(
                try ApplicationEntityRecency(
                    entity: .worktree(worktreeStableKey: launchableWorktree.stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 100)
                )
            )

            let projected = items(
                scope: .repos,
                queryState: .empty,
                recentCommands: [],
                store: store
            )
            let recentRows = projected.filter { $0.group == "Recent Repositories" }
            let row = try #require(recentRows.first)

            #expect(recentRows.count == 1)
            #expect(row.id == "repo-\(launchableRepo.id.uuidString)")
            #expect(row.hasChildren)
            guard case .activateRecent(.repository(let repositoryStableKey)) = row.action else {
                Issue.record("Expected a typed repository-menu activation")
                return
            }
            #expect(repositoryStableKey == launchableRepo.stableKey)
            #expect(row.accessibilityHint == "Show repository actions")
            #expect(row.accessibilityLabel.contains(launchableWorktree.path.path))

            let recentWorktreeRow = try #require(
                projected.first { $0.group == "Recent Worktrees" }
            )
            #expect(recentWorktreeRow.hasChildren)
            #expect(recentWorktreeRow.accessibilityHint == "Show worktree actions")
        }
    }

    @Test("unavailable repositories and their worktrees do not project as recents")
    func unavailableTopologyDoesNotProjectAsRecent() throws {
        try withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology
            )
            let repository = store.addRepo(at: URL(filePath: "/tmp/recency-unavailable-repository"))
            let worktree = try #require(repository.worktrees.first)
            try atoms.applicationEntityRecency.recordOpened(
                repositoryStableKey: repository.stableKey,
                worktreeStableKey: worktree.stableKey,
                at: Date(timeIntervalSince1970: 400)
            )
            store.markRepoUnavailable(repository.id)

            let mainItems = items(
                scope: .everything,
                queryState: .empty,
                recentCommands: [],
                store: store
            )
            let repositoryItems = items(
                scope: .repos,
                queryState: .empty,
                recentCommands: [],
                store: store
            )

            #expect(!mainItems.contains { $0.group == "Recent Repositories" })
            #expect(!repositoryItems.contains { $0.group == "Recent Repositories" })
            #expect(!repositoryItems.contains { $0.group == "Recent Worktrees" })
        }
    }

    private func items(
        scope: CommandBarScope,
        queryState: CommandBarRootQueryState,
        recentCommands: [AppCommand],
        store: WorkspaceStore
    ) -> [CommandBarItem] {
        CommandBarDataSource.items(
            scope: scope,
            rootQueryState: queryState,
            recentCommands: recentCommands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: .shared
        )
    }

    private func groupNames(_ items: [CommandBarItem]) -> [String] {
        CommandBarDataSource.grouped(items).map(\.name)
    }

    private func assertMeaningfulRootsRetainCanonicalRows(
        store: WorkspaceStore,
        recentRepositoryID: UUID,
        remainingRepositoryID: UUID
    ) {
        for scope in [CommandBarScope.everything, .repos, .panes, .commands] {
            let meaningful = items(
                scope: scope,
                queryState: .meaningful,
                recentCommands: [.closeTab],
                store: store
            )
            #expect(!meaningful.contains { $0.group.hasPrefix("Recent") })
            #expect(Set(meaningful.map(\.id)).count == meaningful.count)
        }

        let meaningfulRepositories = items(
            scope: .repos,
            queryState: .meaningful,
            recentCommands: [],
            store: store
        )
        #expect(
            Set(meaningfulRepositories.filter { $0.id.hasPrefix("repo-") }.map(\.id))
                == Set([
                    "repo-\(recentRepositoryID.uuidString)",
                    "repo-\(remainingRepositoryID.uuidString)",
                ])
        )
    }
}
