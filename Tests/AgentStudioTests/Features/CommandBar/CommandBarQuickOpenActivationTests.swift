import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarQuickOpenActivationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private func makeController(
        store: WorkspaceStore = WorkspaceStore()
    ) -> CommandBarPanelController {
        UserDefaults.standard.removeObject(forKey: "CommandBarRecentItemIds")
        UserDefaults.standard.removeObject(forKey: "CommandBarRecentCommands")
        return CommandBarPanelController(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: CommandBarSurfaceAtom()
        )
    }

    private func makeItem(
        id: String,
        action: CommandBarAction
    ) -> CommandBarItem {
        CommandBarItem(
            id: id,
            title: id,
            group: "Test",
            groupPriority: 0,
            action: action
        )
    }

    @Test("Quick Open plain Return opens the live worktree in the current tab")
    func quickOpenPlainReturnUsesCurrentTabAndLiveIdentity() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let store = WorkspaceStore()
            let repositoryPath = URL(filePath: "/tmp/command-bar-quick-open-live")
            let originalRepository = store.addRepo(at: repositoryPath)
            let target = CommandBarQuickOpenTarget.repository(
                repositoryStableKey: originalRepository.stableKey
            )
            let replacementRepositoryID = UUID()
            let replacementWorktree = Worktree(
                repoId: replacementRepositoryID,
                name: "replacement",
                path: repositoryPath,
                isMainWorktree: true
            )
            let replacementRepository = Repo(
                id: replacementRepositoryID,
                name: "replacement",
                repoPath: repositoryPath,
                worktrees: [replacementWorktree]
            )
            let preparation = RepositoryTopologyReplacement.prepare(
                repositories: [replacementRepository],
                watchedPaths: [],
                unavailableRepositoryIDs: []
            )
            guard case .prepared(let replacement) = preparation else {
                Issue.record("Expected valid replacement topology")
                return
            }
            store.repositoryTopologyAtom.replaceTopology(replacement)
            let pane = store.createPane(title: "Current")
            let tab = Tab(paneId: pane.id, name: "Current")
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(pane.id, inTab: tab.id)
            let handler = MockCommandHandler()

            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = handler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let controller = makeController(store: store)
                    controller.state.show(defaultScope: .quickOpen)

                    controller.executeItem(
                        makeItem(id: "quick-open-repository", action: .quickOpen(target))
                    )

                    #expect(handler.executedCommands.count == 1)
                    #expect(handler.executedCommands.first?.0 == .openWorktreeInPane)
                    #expect(handler.executedCommands.first?.1 == replacementWorktree.id)
                    #expect(handler.executedCommands.first?.2 == .worktree)
                    #expect(!controller.state.isVisible)
                }
            )
        }
    }

    @Test("Quick Open plain Return falls back to a new tab and Command-Return always uses a new tab")
    func quickOpenNewTabVariants() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let store = WorkspaceStore()
            let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-quick-open-new-tab"))
            let worktree = try #require(repository.worktrees.first)
            let item = makeItem(
                id: "quick-open-worktree",
                action: .quickOpen(.worktree(worktreeStableKey: worktree.stableKey))
            )
            let handler = MockCommandHandler()

            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = handler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let controller = makeController(store: store)
                    controller.state.show(defaultScope: .quickOpen)
                    controller.executeItem(item)

                    #expect(handler.executedCommands.first?.0 == .openNewTerminalInTab)
                    #expect(handler.executedCommands.first?.1 == worktree.id)
                    #expect(handler.executedCommands.first?.2 == .worktree)

                    let pane = store.createPane(title: "Current")
                    let tab = Tab(paneId: pane.id, name: "Current")
                    store.appendTab(tab)
                    store.setActiveTab(tab.id)
                    store.setActivePane(pane.id, inTab: tab.id)
                    controller.state.show(defaultScope: .quickOpen)
                    controller.executeItem(item, modifier: .command)

                    #expect(handler.executedCommands.count == 2)
                    #expect(handler.executedCommands.last?.0 == .openNewTerminalInTab)
                    #expect(handler.executedCommands.last?.1 == worktree.id)
                    #expect(handler.executedCommands.last?.2 == .worktree)
                }
            )
        }
    }

    @Test("Quick Open Option-Return is unavailable without a current tab")
    func quickOpenOptionReturnRequiresCurrentTab() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let store = WorkspaceStore()
            let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-quick-open-option"))
            let worktree = try #require(repository.worktrees.first)
            let handler = MockCommandHandler()

            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = handler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let controller = makeController(store: store)
                    controller.state.show(defaultScope: .quickOpen)

                    controller.executeItem(
                        makeItem(
                            id: "quick-open-option",
                            action: .quickOpen(.worktree(worktreeStableKey: worktree.stableKey))
                        ),
                        modifier: .option
                    )

                    #expect(handler.executedCommands.isEmpty)
                    #expect(controller.state.isVisible)
                }
            )
        }
    }

    @Test("Quick Open directory Return uses the current tab while Command-Return uses a new tab")
    func quickOpenDirectoryReturnVariants() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let store = WorkspaceStore()
            let pane = store.createPane(title: "Current")
            let tab = Tab(paneId: pane.id, name: "Current")
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(pane.id, inTab: tab.id)
            let directory = FileManager.default.temporaryDirectory.standardizedFileURL
            let item = makeItem(
                id: "quick-open-directory",
                action: .quickOpen(.directory(directory))
            )
            let handler = MockCommandHandler()

            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = handler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let controller = makeController(store: store)
                    controller.state.show(defaultScope: .quickOpen)
                    controller.executeItem(item)

                    #expect(handler.quickOpenDirectoryRequests.count == 1)
                    #expect(handler.quickOpenDirectoryRequests.first?.directory == directory)
                    #expect(handler.quickOpenDirectoryRequests.first?.placement == .currentTabPane)
                    #expect(controller.state.recentItemIds.isEmpty)
                    #expect(!controller.state.isVisible)

                    controller.state.show(defaultScope: .quickOpen)
                    controller.executeItem(item, modifier: .command)

                    #expect(handler.quickOpenDirectoryRequests.count == 2)
                    #expect(handler.quickOpenDirectoryRequests.last?.directory == directory)
                    #expect(handler.quickOpenDirectoryRequests.last?.placement == .newTab)
                    #expect(!controller.state.isVisible)
                }
            )
        }
    }

    @Test("Quick Open rejects a directory that no longer exists")
    func quickOpenRejectsStaleDirectory() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let missingDirectory = FileManager.default.temporaryDirectory
                .appending(path: "missing-quick-open-\(UUID().uuidString)")
            let handler = MockCommandHandler()

            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = handler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let controller = makeController()
                    controller.state.show(defaultScope: .quickOpen)
                    controller.executeItem(
                        makeItem(
                            id: "stale-quick-open-directory",
                            action: .quickOpen(.directory(missingDirectory))
                        )
                    )

                    #expect(handler.quickOpenDirectoryRequests.isEmpty)
                    #expect(controller.state.isVisible)
                }
            )
        }
    }

    @Test("Quick Open actions enter the existing repository menu without dispatching")
    func quickOpenActionsEnterExistingMenu() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let store = WorkspaceStore()
            let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-quick-open-actions"))
            let handler = MockCommandHandler()

            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = handler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let controller = makeController(store: store)
                    controller.state.show(defaultScope: .quickOpen)

                    controller.showActions(
                        for: makeItem(
                            id: "quick-open-actions",
                            action: .quickOpen(
                                .repository(repositoryStableKey: repository.stableKey)
                            )
                        )
                    )

                    #expect(handler.executedCommands.isEmpty)
                    #expect(controller.state.currentLevel?.id == "level-repo-\(repository.id.uuidString)")
                    #expect(controller.state.isVisible)
                }
            )
        }
    }
}
