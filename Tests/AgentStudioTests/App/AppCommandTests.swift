import Foundation
import Testing

@testable import AgentStudio

// MARK: - Mock Command Handler

final class MockCommandHandler: WorkspaceCommandHandling {
    var executedCommands: [(AppCommand, UUID?, SearchItemType?)] = []
    var canExecuteResult: Bool = true
    var targetedCanExecuteResult: Bool?
    var extractedPaneRequests: [(tabId: UUID, paneId: UUID, targetTabIndex: Int?)] = []
    var movePaneRequests: [(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)] = []

    func execute(_ command: AppCommand) {
        executedCommands.append((command, nil, nil))
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        executedCommands.append((command, target, targetType))
    }

    func canExecute(_ command: AppCommand) -> Bool {
        canExecuteResult
    }

    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        _ = command
        _ = target
        _ = targetType
        return targetedCanExecuteResult ?? canExecuteResult
    }

    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        extractedPaneRequests.append((tabId, paneId, targetTabIndex))
    }

    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        movePaneRequests.append((sourcePaneId, sourceTabId, targetTabId))
    }
}

@MainActor
final class MockAppCommandRouter: ShellCommandHandling {
    var handledCommands: [AppCommand] = []
    var handledTargets: [(AppCommand, UUID, SearchItemType)] = []
    var appCommands: Set<AppCommand> = []

    func canExecute(_ command: AppCommand) -> Bool {
        appCommands.contains(command)
    }

    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        _ = target
        _ = targetType
        return canExecute(command)
    }

    func execute(_ command: AppCommand) -> Bool {
        guard appCommands.contains(command) else { return false }
        handledCommands.append(command)
        return true
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        guard appCommands.contains(command) else { return false }
        handledTargets.append((command, target, targetType))
        return true
    }

    func showRepoCommandBar() {}

    func refreshWorktrees() {}

    func refocusActivePane() {}
}

// MARK: - AppCommand Tests

@MainActor
@Suite(.serialized)
final class AppCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    // MARK: - AppCommand Enum

    @Test
    func test_appCommand_allCases_notEmpty() {
        // Assert
        #expect(!(AppCommand.allCases.isEmpty))
    }

    @Test
    func test_appCommand_rawValues_unique() {
        // Arrange
        let rawValues = AppCommand.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)

        // Assert
        #expect(rawValues.count == uniqueValues.count)
    }

    // MARK: - SearchItemType

    @Test
    func test_searchItemType_allCases_containsExpectedTypes() {
        // Assert
        #expect(SearchItemType.allCases.contains(.repo))
        #expect(SearchItemType.allCases.contains(.worktree))
        #expect(SearchItemType.allCases.contains(.tab))
        #expect(SearchItemType.allCases.contains(.pane))
        #expect(SearchItemType.allCases.contains(.floatingTerminal))
    }

    // MARK: - KeyBinding

    @Test
    func test_keyBinding_codable_roundTrip() throws {
        // Arrange
        let binding = KeyBinding(key: "w", modifiers: [.command])

        // Act
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)

        // Assert
        #expect(decoded.key == "w")
        #expect(decoded.modifiers == [.command])
    }

    @Test
    func test_keyBinding_codable_multipleModifiers_roundTrip() throws {
        // Arrange
        let binding = KeyBinding(key: "O", modifiers: [.command, .shift])

        // Act
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)

        // Assert
        #expect(decoded.key == "O")
        #expect(decoded.modifiers.contains(.command))
        #expect(decoded.modifiers.contains(.shift))
    }

    @Test
    func test_keyBinding_hashable_sameBindings_equal() {
        // Arrange
        let b1 = KeyBinding(key: "w", modifiers: [.command])
        let b2 = KeyBinding(key: "w", modifiers: [.command])

        // Assert
        #expect(b1 == b2)
    }

    @Test
    func test_keyBinding_hashable_differentKeys_notEqual() {
        // Arrange
        let b1 = KeyBinding(key: "w", modifiers: [.command])
        let b2 = KeyBinding(key: "q", modifiers: [.command])

        // Assert
        #expect(b1 != b2)
    }

    // MARK: - CommandSpec

    @Test
    func test_commandDefinition_init_defaults() {
        // Act
        let def = CommandSpec(
            command: .closeTab,
            label: "Close Tab",
            icon: .system(.xmark),
            helpText: "Close the active tab"
        )

        // Assert
        #expect(def.command == AppCommand.closeTab)
        #expect(def.label == "Close Tab")
        #expect(def.helpText == "Close the active tab")
        #expect(def.keyBinding == nil)
        #expect(def.icon == .system(.xmark))
        #expect(def.appliesTo.isEmpty)
        #expect(!(def.requiresManagementLayer))
        #expect(def.visibleWhen.isEmpty)
        #expect(def.commandBarGroupName == "Commands")
        #expect(def.commandBarGroupPriority == 8)
        #expect(!def.isHiddenInCommandBar)
    }

    @Test
    func test_commandDefinition_init_full() {
        // Act
        let def = CommandSpec(
            command: .closeWindow,
            shortcut: .closeWindow,
            label: "Close Window",
            icon: .system(.xmark),
            helpText: "Close the active window",
            appliesTo: [.tab],
            requiresManagementLayer: false
        )

        // Assert
        #expect(def.command == AppCommand.closeWindow)
        #expect(def.keyBinding != nil)
        #expect(def.icon == .system(.xmark))
        #expect(def.helpText == "Close the active window")
        #expect(def.appliesTo.contains(SearchItemType.tab))
        #expect(!def.requiresManagementLayer)
    }

    @Test
    func test_toggleSplitZoom_hasDistinctZoomIcon() {
        let splitZoom = CommandDispatcher.shared.definition(for: .toggleSplitZoom)
        let expandPane = CommandDispatcher.shared.definition(for: .expandPane)

        #expect(splitZoom.icon == .system(.plusMagnifyingglass))
        #expect(expandPane.icon == .system(.arrowUpLeftAndArrowDownRight))
        #expect(splitZoom.icon != expandPane.icon)
    }

    // MARK: - CommandDispatcher

    @MainActor

    @Test
    func test_dispatcher_definitions_registered() {
        // Act
        let dispatcher = CommandDispatcher.shared

        // Assert
        #expect(dispatcher.definitions.count == AppCommand.allCases.count)
        #expect(dispatcher.definition(for: .closeTab).command == .closeTab)
        #expect(dispatcher.definition(for: .closePane).command == .closePane)
        #expect(dispatcher.definition(for: .watchFolder).command == .watchFolder)
        #expect(dispatcher.definition(for: .toggleSidebar).command == .toggleSidebar)
    }

    @Test
    func test_toggleSidebar_isVisibleInCommandBar() {
        let definition = CommandDispatcher.shared.definition(for: .toggleSidebar)
        #expect(!definition.isHiddenInCommandBar)
    }

    @Test
    func test_dispatcher_registersDefinitionForEveryCommand() {
        let dispatcher = CommandDispatcher.shared

        for command in AppCommand.allCases {
            let definition = dispatcher.definition(for: command)
            #expect(definition.command == command)
        }
    }

    @Test
    func test_dispatcher_allCommandsHaveHelpText() throws {
        let dispatcher = CommandDispatcher.shared

        for command in AppCommand.allCases {
            let definition = dispatcher.definition(for: command)
            #expect(!definition.helpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @MainActor

    @Test
    func test_dispatcher_closeTab_hasCorrectKeyBinding() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        #expect(def.keyBinding?.key == "w")
        #expect(def.keyBinding?.modifiers == [.command])
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forTab_includesExpected() {
        // Act
        let tabCommands = CommandDispatcher.shared.commands(for: .tab)

        // Assert
        let commandNames = tabCommands.map(\.command)
        #expect(commandNames.contains(.closeTab))
        #expect(commandNames.contains(.breakUpTab))
        #expect(commandNames.contains(.equalizePanes))
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forPane_includesExpected() {
        // Act
        let paneCommands = CommandDispatcher.shared.commands(for: .pane)

        // Assert
        let commandNames = paneCommands.map(\.command)
        #expect(commandNames.contains(.closePane))
        #expect(commandNames.contains(.extractPaneToTab))
        #expect(commandNames.contains(.movePaneToTab))
    }

    @MainActor

    @Test
    func test_arrangementShortcutDefinitions_useTabGroupAndShortcuts() {
        let show = CommandDispatcher.shared.definition(for: .switchArrangement)
        let previous = CommandDispatcher.shared.definition(for: .previousArrangement)
        let next = CommandDispatcher.shared.definition(for: .nextArrangement)

        #expect(show.command == .switchArrangement)
        #expect(show.shortcut == .showArrangementPanel)
        #expect(show.label == "Show Arrangements")
        #expect(show.commandBarGroupName == "Tab")

        #expect(previous.command == .previousArrangement)
        #expect(previous.shortcut == .previousArrangement)
        #expect(previous.label == "Previous Arrangement")
        #expect(previous.commandBarGroupName == "Tab")

        #expect(next.command == .nextArrangement)
        #expect(next.shortcut == .nextArrangement)
        #expect(next.label == "Next Arrangement")
        #expect(next.commandBarGroupName == "Tab")
    }

    @MainActor

    @Test
    func test_terminalScrollAndPromptDefinitions_useTerminalGroupAndShortcuts() {
        let scroll = CommandDispatcher.shared.definition(for: .scrollToBottom)
        let pageUp = CommandDispatcher.shared.definition(for: .scrollPageUp)
        let previousPrompt = CommandDispatcher.shared.definition(for: .jumpToPreviousPrompt)
        let nextPrompt = CommandDispatcher.shared.definition(for: .jumpToNextPrompt)

        #expect(scroll.command == .scrollToBottom)
        #expect(scroll.shortcut == .scrollToBottom)
        #expect(scroll.label == "Scroll to Bottom")
        #expect(scroll.commandBarGroupName == "Terminal")
        #expect(scroll.visibleWhen == [.hasActivePane, .paneIsTerminal])

        #expect(pageUp.command == .scrollPageUp)
        #expect(pageUp.shortcut == .scrollPageUp)
        #expect(pageUp.label == "Page Up")
        #expect(pageUp.commandBarGroupName == "Terminal")
        #expect(pageUp.visibleWhen == [.hasActivePane, .paneIsTerminal])

        #expect(previousPrompt.command == .jumpToPreviousPrompt)
        #expect(previousPrompt.shortcut == .jumpToPreviousPrompt)
        #expect(previousPrompt.label == "Previous Prompt")
        #expect(previousPrompt.commandBarGroupName == "Terminal")
        #expect(previousPrompt.visibleWhen == [.hasActivePane, .paneIsTerminal])

        #expect(nextPrompt.command == .jumpToNextPrompt)
        #expect(nextPrompt.shortcut == .jumpToNextPrompt)
        #expect(nextPrompt.label == "Next Prompt")
        #expect(nextPrompt.commandBarGroupName == "Terminal")
        #expect(nextPrompt.visibleWhen == [.hasActivePane, .paneIsTerminal])
    }

    @MainActor

    @Test
    func test_sidebarAndPaneInboxDefinitions_areCommandBarVisibleWithShortcuts() {
        let sidebarInbox = CommandDispatcher.shared.definition(for: .showInboxNotifications)
        let toggleInboxSort = CommandDispatcher.shared.definition(for: .toggleInboxNotificationSort)
        let clearReadInbox = CommandDispatcher.shared.definition(for: .clearReadInboxNotifications)
        let clearAllInbox = CommandDispatcher.shared.definition(for: .clearAllInboxNotifications)
        let paneInbox = CommandDispatcher.shared.definition(for: .showPaneInboxNotifications)
        let clearPaneInbox = CommandDispatcher.shared.definition(for: .clearPaneInboxNotifications)
        let worktreeSidebar = CommandDispatcher.shared.definition(for: .showWorktreeSidebar)

        #expect(sidebarInbox.shortcut == .showInboxNotifications)
        #expect(!sidebarInbox.isHiddenInCommandBar)
        #expect(toggleInboxSort.label == "Toggle Inbox Sort Order")
        #expect(toggleInboxSort.shortcut == nil)
        #expect(toggleInboxSort.icon == .system(.arrowUpArrowDown))
        #expect(toggleInboxSort.commandBarGroupName == "Inbox")
        #expect(toggleInboxSort.commandBarGroupPriority == sidebarInbox.commandBarGroupPriority)
        #expect(!toggleInboxSort.isHiddenInCommandBar)
        #expect(clearReadInbox.label == "Clear Read Inbox Notifications")
        #expect(clearReadInbox.shortcut == nil)
        #expect(clearReadInbox.icon == .system(.deleteLeft))
        #expect(clearReadInbox.commandBarGroupName == "Inbox")
        #expect(clearReadInbox.commandBarGroupPriority == sidebarInbox.commandBarGroupPriority)
        #expect(!clearReadInbox.isHiddenInCommandBar)
        #expect(clearAllInbox.label == "Clear All Inbox Notifications")
        #expect(clearAllInbox.shortcut == nil)
        #expect(clearAllInbox.icon == .system(.deleteLeft))
        #expect(clearAllInbox.commandBarGroupName == "Inbox")
        #expect(clearAllInbox.commandBarGroupPriority == sidebarInbox.commandBarGroupPriority)
        #expect(!clearAllInbox.isHiddenInCommandBar)
        #expect(paneInbox.shortcut == .showPaneInboxNotifications)
        #expect(paneInbox.appliesTo == [.pane])
        #expect(paneInbox.visibleWhen == [.hasActivePane])
        #expect(paneInbox.commandBarGroupName == "Pane")
        #expect(!paneInbox.isHiddenInCommandBar)
        #expect(clearPaneInbox.label == "Clear Pane Inbox")
        #expect(clearPaneInbox.shortcut == nil)
        #expect(clearPaneInbox.icon == .system(.deleteLeft))
        #expect(clearPaneInbox.helpText.contains("Clear notifications"))
        #expect(clearPaneInbox.commandBarGroupName == "Pane")
        #expect(clearPaneInbox.commandBarGroupPriority == paneInbox.commandBarGroupPriority)
        #expect(worktreeSidebar.shortcut == .showWorktreeSidebar)
        #expect(!worktreeSidebar.isHiddenInCommandBar)
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forRepo_includesExpected() {
        // Act
        let repoCommands = CommandDispatcher.shared.commands(for: .repo)

        // Assert
        let commandNames = repoCommands.map(\.command)
        #expect(commandNames.contains(.removeRepo))
        #expect(!commandNames.contains(.openWorktree))
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_withoutHandler_doesNotCrash() async throws {
        // Arrange
        let dispatcher = CommandDispatcher.shared

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = nil
                dispatcher.appCommandRouter = nil
            },
            body: {
                // Act (should not crash)
                dispatcher.dispatch(.closeTab)
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_canDispatch_withoutHandler_returnsFalse() async throws {
        // Arrange
        let dispatcher = CommandDispatcher.shared

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = nil
                dispatcher.appCommandRouter = nil
            },
            body: {
                // Act
                let result = dispatcher.canDispatch(.closeTab)

                // Assert
                #expect(!(result))
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_callsHandler() async throws {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = nil
            },
            body: {
                // Act
                dispatcher.dispatch(.closeTab)

                // Assert
                #expect(handler.executedCommands.count == 1)
                #expect(handler.executedCommands[0].0 == .closeTab)
                #expect(handler.executedCommands[0].1 == nil)  // no target
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_targeted_callsHandler() async throws {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        let targetId = UUID()

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = nil
            },
            body: {
                // Act
                dispatcher.dispatch(.closeTab, target: targetId, targetType: .tab)

                // Assert
                #expect(handler.executedCommands.count == 1)
                #expect(handler.executedCommands[0].0 == .closeTab)
                #expect(handler.executedCommands[0].1 == targetId)
                #expect(handler.executedCommands[0].2 == .tab)
            }
        )
    }

    @MainActor
    @Test
    func test_dispatcher_dispatch_targeted_usesTargetedAvailability() async throws {
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        handler.canExecuteResult = false
        handler.targetedCanExecuteResult = true
        let targetId = UUID()

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = nil
            },
            body: {
                dispatcher.dispatch(.closeTab, target: targetId, targetType: .tab)

                #expect(handler.executedCommands.count == 1)
                #expect(handler.executedCommands[0].0 == .closeTab)
                #expect(handler.executedCommands[0].1 == targetId)
                #expect(handler.executedCommands[0].2 == .tab)
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_routesAppCommandToAppRouterBeforeHandler() async throws {
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        let appRouter = MockAppCommandRouter()
        appRouter.appCommands = [.watchFolder]

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = appRouter
            },
            body: {
                dispatcher.dispatch(.watchFolder)

                #expect(appRouter.handledCommands == [.watchFolder])
                #expect(handler.executedCommands.isEmpty)
            }
        )
    }

    @Test
    func test_addRepo_rawValue_isRemoved() {
        #expect(AppCommand(rawValue: "addRepo") == nil)
    }

    @MainActor

    @Test
    func test_dispatcher_dispatchTargeted_routesAppCommandToAppRouterBeforeHandler() async throws {
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        let appRouter = MockAppCommandRouter()
        appRouter.appCommands = [.removeRepo]
        let repoId = UUID()

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = appRouter
            },
            body: {
                dispatcher.dispatch(.removeRepo, target: repoId, targetType: .repo)

                #expect(appRouter.handledTargets.count == 1)
                #expect(appRouter.handledTargets[0].0 == .removeRepo)
                #expect(appRouter.handledTargets[0].1 == repoId)
                #expect(appRouter.handledTargets[0].2 == .repo)
                #expect(handler.executedCommands.isEmpty)
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_dispatchExtractPaneToTab_callsHandlerSurface() async throws {
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()

        let tabId = UUID()
        let paneId = UUID()

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = nil
            },
            body: {
                dispatcher.dispatchExtractPaneToTab(tabId: tabId, paneId: paneId, targetTabIndex: 2)

                #expect(handler.extractedPaneRequests.count == 1)
                #expect(handler.extractedPaneRequests[0].tabId == tabId)
                #expect(handler.extractedPaneRequests[0].paneId == paneId)
                #expect(handler.extractedPaneRequests[0].targetTabIndex == 2)
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_dispatchMovePaneToTab_callsHandlerSurface() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let dispatcher = CommandDispatcher.shared
            let handler = MockCommandHandler()
            atom(\.managementLayer).deactivate()

            let sourcePaneId = UUID()
            let sourceTabId = UUID()
            let targetTabId = UUID()

            try await withIsolatedCommandDispatcher(
                configure: {
                    dispatcher.handler = handler
                    dispatcher.appCommandRouter = nil
                },
                body: {
                    atom(\.managementLayer).toggle()
                    defer { atom(\.managementLayer).deactivate() }

                    dispatcher.dispatchMovePaneToTab(
                        sourcePaneId: sourcePaneId,
                        sourceTabId: sourceTabId,
                        targetTabId: targetTabId
                    )

                    let request = try #require(handler.movePaneRequests.first)
                    #expect(handler.movePaneRequests.count == 1)
                    #expect(request.sourcePaneId == sourcePaneId)
                    #expect(request.sourceTabId == sourceTabId)
                    #expect(request.targetTabId == targetTabId)
                }
            )
        }
    }

    @MainActor

    @Test
    func test_dispatcher_cannotDispatch_whenHandlerReturnsFalse() async throws {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        handler.canExecuteResult = false

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = nil
            },
            body: {
                // Act
                dispatcher.dispatch(.closeTab)

                // Assert — command should not have been executed
                #expect(handler.executedCommands.isEmpty)
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_closePane_requiresManagementLayer() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closePane)

        // Assert
        #expect(def.requiresManagementLayer)
    }

    @MainActor

    @Test
    func test_dispatcher_movePaneToTab_requiresManagementLayer() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .movePaneToTab)

        // Assert
        #expect(def.requiresManagementLayer)
        #expect(def.appliesTo.contains(.pane))
    }

    @MainActor

    @Test
    func test_dispatcher_closeTab_doesNotRequireManagementLayer() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        #expect(!def.requiresManagementLayer)
    }

    @MainActor

    @Test
    func test_dispatcher_managementRequiredCommand_blockedWhenInactive() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let dispatcher = CommandDispatcher.shared
            let handler = MockCommandHandler()
            atom(\.managementLayer).deactivate()

            try await withIsolatedCommandDispatcher(
                configure: {
                    dispatcher.handler = handler
                    dispatcher.appCommandRouter = nil
                },
                body: {
                    defer { atom(\.managementLayer).deactivate() }

                    #expect(!dispatcher.canDispatch(.closePane))
                    #expect(!dispatcher.canDispatch(.movePaneToTab))
                }
            )
        }
    }

    @MainActor

    @Test
    func test_dispatcher_managementRequiredCommand_allowedWhenActive() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let dispatcher = CommandDispatcher.shared
            let handler = MockCommandHandler()
            atom(\.managementLayer).deactivate()

            try await withIsolatedCommandDispatcher(
                configure: {
                    dispatcher.handler = handler
                    dispatcher.appCommandRouter = nil
                },
                body: {
                    atom(\.managementLayer).toggle()
                    defer { atom(\.managementLayer).deactivate() }

                    #expect(dispatcher.canDispatch(.closePane))
                    #expect(dispatcher.canDispatch(.movePaneToTab))
                }
            )
        }
    }

    // MARK: - Sidebar Commands

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_registered() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def.label == "Filter Sidebar")
        #expect(def.icon == .system(.magnifyingglass))
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_hasCorrectKeyBinding() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def.keyBinding?.key == "f")
        #expect(def.keyBinding?.modifiers.contains(.command) ?? false)
        #expect(!(def.keyBinding?.modifiers.contains(.shift) ?? false))
    }

    @MainActor

    @Test
    func test_dispatcher_openNewTerminalInTab_registered() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        #expect(def.label == "Open Terminal in New Tab")
        #expect(def.icon == .system(.terminalFill))
        #expect(def.helpText == "Open a worktree in a fresh terminal tab")
    }

    @MainActor

    @Test
    func test_dispatcher_openNewTerminalInTab_appliesToWorktree() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        #expect(def.appliesTo.contains(.worktree))
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forWorktree_includesOpenNewTerminal() {
        // Act
        let worktreeCommands = CommandDispatcher.shared.commands(for: .worktree)

        // Assert
        let commandNames = worktreeCommands.map(\.command)
        #expect(commandNames.contains(.openNewTerminalInTab))
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_doesNotRequireManagementLayer() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(!def.requiresManagementLayer)
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_noAppliesTo() {
        // Act — filterSidebar is a global command, not tied to an item type
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def.appliesTo.isEmpty)
    }

    // MARK: - Webview Commands

    @MainActor

    @Test
    func test_dispatcher_openWebview_registered() {
        let def = CommandDispatcher.shared.definition(for: .openWebview)
        #expect(def.label == "Open New Webview Tab")
        #expect(def.icon == .system(.globe))
    }

    @MainActor

    @Test
    func test_dispatcher_openWebview_noKeyBinding() {
        let def = CommandDispatcher.shared.definition(for: .openWebview)
        #expect(def.keyBinding == nil)
    }

    @MainActor

    @Test
    func test_dispatcher_signInGitHub_registered() {
        let def = CommandDispatcher.shared.definition(for: .signInGitHub)
        #expect(def.label == "Sign in to GitHub")
        #expect(def.icon == .system(.personBadgeKey))
    }

    @MainActor

    @Test
    func test_dispatcher_signInGoogle_registered() {
        let def = CommandDispatcher.shared.definition(for: .signInGoogle)
        #expect(def.label == "Sign in to Google")
        #expect(def.icon == .system(.personBadgeKey))
    }

    @MainActor

    @Test
    func test_dispatcher_signIn_noKeyBindings() {
        // Sign-in commands are invoked from command bar, no global shortcuts
        #expect(CommandDispatcher.shared.definition(for: .signInGitHub).keyBinding == nil)
        #expect(CommandDispatcher.shared.definition(for: .signInGoogle).keyBinding == nil)
    }
}
