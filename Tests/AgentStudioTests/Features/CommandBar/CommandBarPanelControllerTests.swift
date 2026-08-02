import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Foundation
import Testing

@testable import AgentStudioCommandBar
@testable import AgentStudioCore

@MainActor
func makeCommandBarTestOcticonLoader(from testFilePath: String = #filePath) -> OcticonLoader {
    OcticonLoader(
        resourceRootURL: testAgentStudioResourceRootURL(from: testFilePath)
    )
}

@MainActor
@Suite(.serialized)
struct CommandBarPanelControllerTests {

    private let window: NSWindow

    init() {
        installTestCoreAtomsIfNeeded()
        // Offscreen window — never displayed, lightweight test double
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
    }

    private func makeController(
        store: WorkspaceStore = WorkspaceStore(),
        dispatcher: any AppCommandDispatching = FakeAppCommandDispatcher(),
        commandBarSurface: CommandBarSurfaceAtom = CommandBarSurfaceAtom()
    ) -> CommandBarPanelController {
        UserDefaults.standard.removeObject(forKey: "CommandBarRecentItemIds")
        UserDefaults.standard.removeObject(forKey: "CommandBarRecentCommands")
        return CommandBarPanelController(
            store: store,
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher,
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: commandBarSurface
        )
    }

    private func makeItem(
        id: String,
        action: CommandBarAction,
        command: AppCommand? = nil
    ) -> CommandBarItem {
        CommandBarItem(
            id: id,
            title: id,
            group: "Test",
            groupPriority: 0,
            action: action,
            command: command
        )
    }

    @Test
    func test_init_stateIsNotVisible() {
        let controller = makeController()

        // Assert
        #expect(!controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.navigationStack.isEmpty)
    }

    // MARK: - Show via Public API

    @Test
    func test_show_noPrefix_setsStateVisible() {
        let controller = makeController()

        // Act
        controller.show(parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.activeScope == .everything)
    }

    @Test
    func test_show_withCommandPrefix_setsCommandScope() {
        let controller = makeController()

        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "> ")
        #expect(controller.state.activeScope == .commands)
    }

    @Test
    func test_show_withPanePrefix_setsPaneScope() {
        let controller = makeController()

        // Act
        controller.show(prefix: "$", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "$ ")
        #expect(controller.state.activeScope == .panes)
    }

    @Test
    func test_show_publishesCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let workspaceWindowId = UUID()
        let controller = makeController(commandBarSurface: commandBarSurface)

        controller.show(prefix: ">", parentWindow: window, workspaceWindowId: workspaceWindowId)

        #expect(commandBarSurface.activeScope == .commands)
        #expect(commandBarSurface.activeScope(for: workspaceWindowId) == .commands)
    }

    @Test
    func test_showWithoutWorkspaceWindowIdDoesNotPublishSyntheticSurface() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let controller = makeController(commandBarSurface: commandBarSurface)

        controller.show(prefix: ">", parentWindow: window)

        #expect(controller.state.isVisible)
        #expect(commandBarSurface.activeScope == nil)
    }

    @Test
    func test_switchPrefix_updatesCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let workspaceWindowId = UUID()
        let controller = makeController(commandBarSurface: commandBarSurface)

        controller.show(prefix: ">", parentWindow: window, workspaceWindowId: workspaceWindowId)
        controller.show(prefix: "$", parentWindow: window, workspaceWindowId: workspaceWindowId)

        #expect(commandBarSurface.activeScope == .panes)
        #expect(commandBarSurface.activeScope(for: workspaceWindowId) == .panes)
    }

    @Test
    func test_show_visibleCommandBar_movesSurfaceToNewWindow() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let controller = makeController(commandBarSurface: commandBarSurface)

        controller.show(prefix: ">", parentWindow: window, workspaceWindowId: firstWindowId)
        controller.show(prefix: "$", parentWindow: window, workspaceWindowId: secondWindowId)

        #expect(commandBarSurface.activeScope(for: firstWindowId) == nil)
        #expect(commandBarSurface.activeScope(for: secondWindowId) == .panes)
    }

    // MARK: - Dismiss via Public API

    @Test
    func test_dismiss_afterShow_resetsState() {
        let controller = makeController()
        #expect(!controller.state.isVisible)

        // Arrange
        controller.show(parentWindow: window)
        #expect(controller.state.isVisible)

        // Act
        controller.dismiss()

        // Assert
        #expect(!controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
    }

    @Test
    func test_dismiss_clearsCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let workspaceWindowId = UUID()
        let controller = makeController(commandBarSurface: commandBarSurface)
        controller.show(parentWindow: window, workspaceWindowId: workspaceWindowId)

        controller.dismiss()

        #expect(commandBarSurface.activeScope == nil)
        #expect(commandBarSurface.activeScope(for: workspaceWindowId) == nil)
    }

    @Test
    func test_dismiss_whenNotVisible_noOp() {
        let controller = makeController()

        // Arrange — not visible
        #expect(!controller.state.isVisible)

        // Act — should not crash or change state
        controller.dismiss()

        // Assert
        #expect(!controller.state.isVisible)
    }

    // MARK: - Same Scope Behavior (same prefix preserves state)

    @Test
    func test_show_samePrefixTwice_preservesState() {
        let controller = makeController()

        // Arrange — show with no prefix
        controller.show(parentWindow: window)
        #expect(controller.state.isVisible)
        controller.state.rawInput = "dra"

        // Act — show again with same prefix (nil)
        controller.show(parentWindow: window)

        // Assert — should stay open and preserve state
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "dra")
    }

    @Test
    func test_show_sameCommandPrefixTwice_preservesQueryAndNavigation() {
        let controller = makeController()

        // Arrange
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.isVisible)
        controller.state.rawInput = "> close"
        controller.state.selectedIndex = 2
        let level = makeCommandBarLevel(id: "close-tab", title: "Close Tab", parentLabel: "Tab")
        controller.state.pushLevel(level)

        // Act
        controller.show(prefix: ">", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.isNested)
        #expect(controller.state.selectedIndex == 0)
    }

    // MARK: - Switch Behavior (different prefix → switch in-place)

    @Test
    func test_show_differentPrefix_switchesInPlace() {
        let controller = makeController()

        // Arrange — open with no prefix
        controller.show(parentWindow: window)
        #expect(controller.state.activeScope == .everything)

        // Act — show with command prefix
        controller.show(prefix: ">", parentWindow: window)

        // Assert — switched, still visible
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "> ")
        #expect(controller.state.activeScope == .commands)
    }

    @Test
    func test_show_switchFromCommandToPane_switchesInPlace() {
        let controller = makeController()

        // Arrange — open with ">"
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.activeScope == .commands)

        // Act — switch to "$"
        controller.show(prefix: "$", parentWindow: window)

        // Assert
        #expect(controller.state.isVisible)
        #expect(controller.state.rawInput == "$ ")
        #expect(controller.state.activeScope == .panes)
    }

    // MARK: - Full Lifecycle

    @Test
    func test_fullLifecycle_showQueryPushDismiss() {
        let controller = makeController()

        // Act — show
        controller.show(prefix: ">", parentWindow: window)
        #expect(controller.state.isVisible)

        // Act — simulate user typing a query
        controller.state.rawInput = "> close"
        #expect(controller.state.searchQuery == "close")

        // Act — push into nested level
        let level = makeCommandBarLevel(id: "close-tab", title: "Close Tab", parentLabel: "Tab")
        controller.state.pushLevel(level)
        #expect(controller.state.isNested)

        // Act — dismiss via public API
        controller.dismiss()

        // Assert — everything reset
        #expect(!controller.state.isVisible)
        #expect(!controller.state.isNested)
        #expect(controller.state.rawInput.isEmpty)
        #expect(controller.state.selectedIndex == 0)
    }

    @Test("recent repository activation resolves and opens the live repository menu")
    func recentRepositoryActivationOpensLiveRepositoryMenu() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-recent-main"))
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(store: store, dispatcher: dispatcher)
            controller.state.show(prefix: "#")

            controller.executeItem(
                makeItem(
                    id: "recent-repository",
                    action: .activateRecent(
                        .repository(repositoryStableKey: repository.stableKey)
                    )
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(controller.state.currentLevel?.id == "level-repo-\(repository.id.uuidString)")
            #expect(controller.state.currentLevel?.title == repository.name)
            #expect(controller.state.isVisible)
        }
    }

    @Test("recent repository activation re-resolves a replacement with the same stable key")
    func recentRepositoryActivationReResolvesLiveIdentity() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repositoryPath = URL(filePath: "/tmp/command-bar-recent-reresolve")
            let oldRepositoryID = UUID()
            let oldWorktree = Worktree(
                repoId: oldRepositoryID,
                name: "old",
                path: repositoryPath,
                isMainWorktree: true
            )
            let oldRepository = Repo(
                id: oldRepositoryID,
                name: "old",
                repoPath: repositoryPath,
                worktrees: [oldWorktree]
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
            store.repositoryTopologyAtom.replaceTopology(
                try #require(
                    RepositoryTopologyReplacement.prepare(
                        repositories: [oldRepository],
                        watchedPaths: [],
                        unavailableRepositoryIDs: []
                    ).preparedValue
                )
            )
            let activation = CommandBarRecentActivation.repository(
                repositoryStableKey: oldRepository.stableKey
            )
            store.repositoryTopologyAtom.replaceTopology(
                try #require(
                    RepositoryTopologyReplacement.prepare(
                        repositories: [replacementRepository],
                        watchedPaths: [],
                        unavailableRepositoryIDs: []
                    ).preparedValue
                )
            )
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(store: store, dispatcher: dispatcher)
            controller.state.show(prefix: "#")

            controller.executeItem(
                makeItem(id: "recent-repository", action: .activateRecent(activation))
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(
                controller.state.currentLevel?.id
                    == "level-repo-\(replacementRepository.id.uuidString)"
            )
            #expect(controller.state.currentLevel?.title == replacementRepository.name)
            #expect(controller.state.currentLevel?.id != "level-repo-\(oldRepository.id.uuidString)")
            #expect(controller.state.isVisible)
        }
    }

    @Test("recent worktree activation resolves and opens the live worktree menu")
    func recentWorktreeActivationOpensLiveWorktreeMenu() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-recent-worktree"))
            let worktree = try #require(repository.worktrees.first)
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(store: store, dispatcher: dispatcher)
            controller.state.show(prefix: "#")

            controller.executeItem(
                makeItem(
                    id: "recent-worktree",
                    action: .activateRecent(
                        .worktree(worktreeStableKey: worktree.stableKey)
                    )
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(controller.state.currentLevel?.id == "level-wt-\(worktree.id.uuidString)")
            #expect(controller.state.currentLevel?.title == worktree.name)
            #expect(controller.state.isVisible)
        }
    }

    @Test("stale recent activation dispatches nothing, prunes the hint, and keeps the panel usable")
    func staleRecentActivationDoesNotDispatch() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let stableKey = String(repeating: "a", count: 16)
            atoms.applicationEntityRecency.hydrate([
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 1)
                )
            ])
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(dispatcher: dispatcher)
            controller.state.show(prefix: "#")

            controller.executeItem(
                makeItem(
                    id: "stale-repository",
                    action: .activateRecent(
                        .repository(repositoryStableKey: stableKey)
                    )
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(atoms.applicationEntityRecency.recentEntities.isEmpty)
            #expect(controller.state.isVisible)
            #expect(controller.state.selectedIndex == 0)
        }
    }

    @Test("recent repository activation rejects a repository that lost every worktree")
    func recentRepositoryActivationRejectsRepositoryWithoutWorktrees() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore()
            let repository = store.addRepo(
                at: URL(filePath: "/tmp/command-bar-recent-repository-without-worktrees")
            )
            atoms.applicationEntityRecency.record(
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: repository.stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 1)
                )
            )
            store.repositoryTopologyAtom.replaceTopology(
                try #require(
                    RepositoryTopologyReplacement.prepare(
                        repositories: [
                            Repo(
                                id: repository.id,
                                name: repository.name,
                                repoPath: repository.repoPath,
                                worktrees: []
                            )
                        ],
                        watchedPaths: [],
                        unavailableRepositoryIDs: []
                    ).preparedValue
                )
            )
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(store: store, dispatcher: dispatcher)
            controller.state.show(prefix: "#")

            controller.executeItem(
                makeItem(
                    id: "recent-repository",
                    action: .activateRecent(
                        .repository(repositoryStableKey: repository.stableKey)
                    )
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(controller.state.currentLevel == nil)
            #expect(controller.state.isVisible)
            #expect(atoms.applicationEntityRecency.recentEntities.isEmpty)
        }
    }

    @Test("stale recent worktree activation dispatches nothing and prunes only that hint")
    func staleRecentWorktreeActivationDoesNotDispatch() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let staleStableKey = String(repeating: "b", count: 16)
            let retainedStableKey = String(repeating: "c", count: 16)
            atoms.applicationEntityRecency.hydrate([
                try ApplicationEntityRecency(
                    entity: .worktree(worktreeStableKey: staleStableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 2)
                ),
                try ApplicationEntityRecency(
                    entity: .worktree(worktreeStableKey: retainedStableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 1)
                ),
            ])
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(dispatcher: dispatcher)
            controller.state.show(prefix: "#")

            controller.executeItem(
                makeItem(
                    id: "stale-worktree",
                    action: .activateRecent(
                        .worktree(worktreeStableKey: staleStableKey)
                    )
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(
                atoms.applicationEntityRecency.recentEntities.map(\.entity)
                    == [.worktree(worktreeStableKey: retainedStableKey)]
            )
            #expect(controller.state.isVisible)
            #expect(controller.state.selectedIndex == 0)
        }
    }

    @Test("unavailable recent repository and worktree activations prune without dispatch")
    func unavailableRecentApplicationActivationsDoNotDispatch() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore()
            let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-unavailable-recent"))
            let worktree = try #require(repository.worktrees.first)
            try atoms.applicationEntityRecency.recordOpened(
                repositoryStableKey: repository.stableKey,
                worktreeStableKey: worktree.stableKey,
                at: Date(timeIntervalSince1970: 3)
            )
            store.markRepoUnavailable(repository.id)
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(store: store, dispatcher: dispatcher)
            controller.state.show(prefix: "#")

            controller.executeItem(
                makeItem(
                    id: "unavailable-repository",
                    action: .activateRecent(
                        .repository(repositoryStableKey: repository.stableKey)
                    )
                )
            )
            controller.executeItem(
                makeItem(
                    id: "unavailable-worktree",
                    action: .activateRecent(
                        .worktree(worktreeStableKey: worktree.stableKey)
                    )
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(atoms.applicationEntityRecency.recentEntities.isEmpty)
            #expect(controller.state.isVisible)
        }
    }

    @Test("eligible recent pane activation dispatches the validated focus command")
    func recentPaneActivationDispatchesValidatedFocus() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(identityAtom: atoms.workspaceIdentity)
            let pane = store.createPane(title: "Target")
            let tab = Tab(paneId: pane.id, name: "Target")
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(pane.id, inTab: tab.id)
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(store: store, dispatcher: dispatcher)
            controller.state.show(prefix: "$")

            controller.executeItem(
                makeItem(
                    id: "recent-pane",
                    action: .activateRecent(
                        .pane(
                            paneID: pane.id,
                            workspaceID: store.identityAtom.workspaceId
                        )
                    )
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.first?.command == .focusPane)
            #expect(dispatcher.targetedDispatches.first?.target == pane.id)
            #expect(dispatcher.targetedDispatches.first?.targetType == .floatingTerminal)
            #expect(!controller.state.isVisible)
        }
    }

    @Test("recent and ordinary pane rows dispatch focus through the feature boundary and dismiss")
    func paneRowsDispatchFocusThroughFeatureBoundaryAndDismiss() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(identityAtom: atoms.workspaceIdentity)
            let firstPane = store.createPane(title: "First")
            let secondPane = store.createPane(title: "Second")
            let firstTab = Tab(paneId: firstPane.id, name: "First")
            let secondTab = Tab(paneId: secondPane.id, name: "Second")
            store.appendTab(firstTab)
            store.appendTab(secondTab)
            store.setActiveTab(firstTab.id)
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.identityAtom.workspaceId,
                recentEntities: [
                    try WorkspaceEntityRecency(
                        workspaceID: store.identityAtom.workspaceId,
                        entity: .pane(paneID: secondPane.id),
                        interaction: .focused,
                        lastInteractedAt: Date(timeIntervalSince1970: 1)
                    )
                ]
            )
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(store: store, dispatcher: dispatcher)
            controller.state.show(prefix: "$")
            let recentPaneItem = try #require(
                CommandBarDataSource.items(
                    scope: .panes,
                    store: store,
                    repoCache: RepoCacheAtom(),
                    dispatcher: dispatcher
                )
                .first {
                    $0.group == "Recent Panes"
                        && $0.id == "pane-\(secondPane.id.uuidString)"
                }
            )

            controller.executeItem(recentPaneItem)

            #expect(dispatcher.targetedDispatches.count == 1)
            #expect(dispatcher.targetedDispatches[0].command == .focusPane)
            #expect(dispatcher.targetedDispatches[0].target == secondPane.id)
            #expect(dispatcher.targetedDispatches[0].targetType == .floatingTerminal)
            #expect(!controller.state.isVisible)

            controller.state.show(prefix: "$")
            let ordinaryPaneItem = try #require(
                CommandBarDataSource.items(
                    scope: .panes,
                    store: store,
                    repoCache: RepoCacheAtom(),
                    dispatcher: dispatcher
                )
                .first {
                    $0.group != "Recent Panes"
                        && $0.id == "pane-\(firstPane.id.uuidString)"
                }
            )

            controller.executeItem(ordinaryPaneItem)

            #expect(dispatcher.targetedDispatches.count == 2)
            #expect(dispatcher.targetedDispatches[1].command == .focusPane)
            #expect(dispatcher.targetedDispatches[1].target == firstPane.id)
            #expect(dispatcher.targetedDispatches[1].targetType == .floatingTerminal)
            #expect(!controller.state.isVisible)
        }
    }

    @Test("Commands-root direct dispatch records typed command history after acceptance")
    func commandsRootDirectDispatchRecordsCommand() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(dispatcher: dispatcher)
            controller.state.show(prefix: ">")

            controller.executeItem(
                makeItem(
                    id: "close-tab",
                    action: .dispatch(.closeTab),
                    command: .closeTab
                )
            )

            #expect(dispatcher.dispatchedCommands == [.closeTab])
            #expect(controller.state.recentCommands.first == .closeTab)
        }
    }

    @Test("Commands-root targeted dispatch records only after a valid target begins dispatch")
    func commandsRootTargetedDispatchRecordsOnlyAcceptedCommand() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let dispatcher = FakeAppCommandDispatcher()
            let target = UUID()
            let controller = makeController(dispatcher: dispatcher)
            controller.state.show(prefix: ">")

            dispatcher.availableCommands.remove(.focusPane)
            controller.executeItem(
                makeItem(
                    id: "rejected-focus",
                    action: .dispatchTargeted(.focusPane, target: target, targetType: .pane),
                    command: .focusPane
                )
            )
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(controller.state.recentCommands.isEmpty)
            #expect(controller.state.isVisible)

            dispatcher.availableCommands.insert(.focusPane)
            controller.executeItem(
                makeItem(
                    id: "accepted-focus",
                    action: .dispatchTargeted(.focusPane, target: target, targetType: .pane),
                    command: .focusPane
                )
            )
            #expect(dispatcher.targetedDispatches.count == 1)
            #expect(dispatcher.targetedDispatches[0].command == .focusPane)
            #expect(dispatcher.targetedDispatches[0].target == target)
            #expect(dispatcher.targetedDispatches[0].targetType == .pane)
            #expect(controller.state.recentCommands == [.focusPane])
        }
    }

    @Test("Commands-root drill-in records no command history")
    func commandsRootDrillInDoesNotRecordCommand() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let dispatcher = FakeAppCommandDispatcher()
            let controller = makeController(dispatcher: dispatcher)
            controller.state.show(prefix: ">")
            let level = makeCommandBarLevel(id: "targets", title: "Targets")

            controller.executeItem(
                makeItem(
                    id: "targeted-command",
                    action: .navigate(level),
                    command: .focusPane
                )
            )

            #expect(dispatcher.dispatchedCommands.isEmpty)
            #expect(dispatcher.targetedDispatches.isEmpty)
            #expect(controller.state.recentCommands.isEmpty)
            #expect(controller.state.currentLevel?.id == level.id)
        }
    }

    @Test("activation completion is rejected after dismissal or scope-session change")
    func activationGenerationRejectsChangedRootSession() {
        var gate = CommandBarActivationGenerationGate()
        let workspaceID = UUID()
        let activation = gate.begin(
            rootSessionGeneration: 10,
            workspaceID: workspaceID
        )

        #expect(
            gate.accepts(
                activation,
                rootSessionGeneration: 10,
                workspaceID: workspaceID
            )
        )
        #expect(
            !gate.accepts(
                activation,
                rootSessionGeneration: 11,
                workspaceID: workspaceID
            )
        )
    }

    @Test("activation completion is rejected after workspace change")
    func activationGenerationRejectsChangedWorkspace() {
        var gate = CommandBarActivationGenerationGate()
        let activation = gate.begin(
            rootSessionGeneration: 10,
            workspaceID: UUID()
        )

        #expect(
            !gate.accepts(
                activation,
                rootSessionGeneration: 10,
                workspaceID: UUID()
            )
        )
    }

    @Test("a superseding activation invalidates earlier completion")
    func activationGenerationRejectsSupersededActivation() {
        var gate = CommandBarActivationGenerationGate()
        let workspaceID = UUID()
        let first = gate.begin(
            rootSessionGeneration: 10,
            workspaceID: workspaceID
        )
        let second = gate.begin(
            rootSessionGeneration: 10,
            workspaceID: workspaceID
        )

        #expect(
            !gate.accepts(
                first,
                rootSessionGeneration: 10,
                workspaceID: workspaceID
            )
        )
        #expect(
            gate.accepts(
                second,
                rootSessionGeneration: 10,
                workspaceID: workspaceID
            )
        )
    }
}

extension RepositoryTopologyReplacementPreparation {
    fileprivate var preparedValue: RepositoryTopologyReplacement? {
        guard case .prepared(let replacement) = self else { return nil }
        return replacement
    }
}
