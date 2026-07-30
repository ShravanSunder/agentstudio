import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCommandBar
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

// MARK: - Mock Command Handler

final class MockCommandHandler: WorkspaceCommandHandling {
    var executedCommands: [(AppCommand, UUID?, SearchItemType?)] = []
    var quickOpenDirectoryRequests: [(directory: URL, placement: QuickOpenDirectoryPlacement)] = []
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

    func executeQuickOpenDirectory(_ directory: URL, placement: QuickOpenDirectoryPlacement) {
        quickOpenDirectoryRequests.append((directory, placement))
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
    var handledRequests: [AppCommandExecutionRequest] = []
    var appCommands: Set<AppCommand> = []
    var requestCommands: Set<AppCommand>?
    var parameterlessCanExecuteResult: Bool?

    func canExecute(_ command: AppCommand) -> Bool {
        parameterlessCanExecuteResult ?? appCommands.contains(command)
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

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        guard (requestCommands ?? appCommands).contains(request.command) else { return .unsupportedCommand }
        handledRequests.append(request)
        return .applied
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
        installTestCoreAtomsIfNeeded()
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

    @Test
    func launcherCommandsExposeInlineControlSurface() {
        #expect(
            AppCommand.showCommandBarEverything.definition.surfacePolicy
                .exposes(.inlineControl)
        )
        #expect(
            AppCommand.showCommandBarRepos.definition.surfacePolicy
                .exposes(.inlineControl)
        )
        #expect(
            AppCommand.watchFolder.definition.surfacePolicy
                .exposes(.inlineControl)
        )
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

    // MARK: - AppCommandSpec

    @Test
    func test_commandDefinition_init_defaults() {
        // Act
        let def = AppCommandSpec(
            command: .closeTab,
            label: "Close Tab",
            icon: .system(.xmark),
            helpText: "Close the active tab",
            surfacePolicy: .exposed([.commandBar]),
            targeting: .contextual
        )

        // Assert
        #expect(def.command == AppCommand.closeTab)
        #expect(def.label == "Close Tab")
        #expect(def.helpText == "Close the active tab")
        #expect(def.keyBinding == nil)
        #expect(def.icon == .system(.xmark))
        #expect(def.surfacePolicy == .exposed([.commandBar]))
        #expect(def.surfacePolicy.exposes(.commandBar))
        #expect(def.targeting == .contextual)
        #expect(!(def.requiresManagementLayer))
        #expect(def.visibleWhen.isEmpty)
        #expect(def.commandBarGroupName == "Commands")
        #expect(def.commandBarGroupPriority == 8)
    }

    @Test
    func test_commandDefinition_init_full() {
        // Act
        let def = AppCommandSpec(
            command: .closeWindow,
            shortcut: .closeWindow,
            label: "Close Window",
            icon: .system(.xmark),
            helpText: "Close the active window",
            surfacePolicy: .exposed([.mainMenu]),
            targeting: .contextual,
            requiresManagementLayer: false
        )

        // Assert
        #expect(def.command == AppCommand.closeWindow)
        #expect(def.keyBinding != nil)
        #expect(def.icon == .system(.xmark))
        #expect(def.helpText == "Close the active window")
        #expect(def.surfacePolicy == .exposed([.mainMenu]))
        #expect(def.targeting == .contextual)
        #expect(!def.requiresManagementLayer)
    }

    @Test
    func test_zoomPane_presentsForSinglePaneTabsWithNarrowHeadlessIPC() {
        let zoomPane = AppCommandDispatcher.shared.definition(for: .zoomPane)
        let expandPane = AppCommandDispatcher.shared.definition(for: .expandPane)
        let ipcEntry = zoomPane.ipcCommandListEntry
        let canonicalZoomSymbol = SystemSymbol(
            rawValue: "square.arrowtriangle.4.outward"
        )

        #expect(zoomPane.label == "Pane Zoom")
        #expect(zoomPane.helpText == "Zoom the active pane")
        #expect(
            zoomPane.surfacePolicy
                == .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom), .inlineControl])
        )
        #expect(
            zoomPane.targeting
                == .contextualAndTargeted([.pane], preferredInvocation: .contextual)
        )
        #expect(!zoomPane.visibleWhen.contains(.hasMultiplePanes))
        #expect(zoomPane.icon == canonicalZoomSymbol.map(CommandIcon.system))
        #expect(expandPane.icon == .system(.arrowUpLeftAndArrowDownRight))
        #expect(zoomPane.icon != expandPane.icon)
        #expect(ipcEntry.executionModes == [.headless])
        #expect(ipcEntry.targetKinds == [.pane])
        #expect(ipcEntry.requiredPrivileges == [.layoutMutate])
    }

    @Test
    func test_zoomPane_hardCutPreservesInputFocusCommandIdentities() {
        #expect(AppCommand.zoomPane.rawValue == "zoomPane")
        #expect(AppCommand(rawValue: "focus") == nil)
        #expect(AppCommand.focusPane.rawValue == "focusPane")
        #expect(AppCommand.focusPaneLeft.rawValue == "focusPaneLeft")
        #expect(AppCommand.focusPaneRight.rawValue == "focusPaneRight")
        #expect(AppCommand.focusPaneUp.rawValue == "focusPaneUp")
        #expect(AppCommand.focusPaneDown.rawValue == "focusPaneDown")
        #expect(AppCommand.focusNextPane.rawValue == "focusNextPane")
        #expect(AppCommand.focusPrevPane.rawValue == "focusPrevPane")
        #expect(AppCommand.focusDrawerPaneUp.rawValue == "focusDrawerPaneUp")
        #expect(AppCommand.focusDrawerPaneLeft.rawValue == "focusDrawerPaneLeft")
        #expect(AppCommand.focusDrawerPaneDown.rawValue == "focusDrawerPaneDown")
        #expect(AppCommand.focusDrawerPaneRight.rawValue == "focusDrawerPaneRight")
    }

    @Test
    func test_commandCatalog_exposesOneContextualZoomViewerCommand() throws {
        let viewerDefinitions = AppCommand.allCases
            .map(\.definition)
            .filter { $0.label == "Worktree Viewer" }

        let viewer = try #require(viewerDefinitions.first)
        #expect(viewerDefinitions.count == 1)
        #expect(viewer.command == .showViewer)
        #expect(
            viewer.surfacePolicy
                == .exposed([.commandBar, .toolbar(.terminalZoom)])
        )
        #expect(
            viewer.targeting
                == .contextualAndTargeted([.pane], preferredInvocation: .contextual)
        )
        #expect(viewer.visibleWhen == [.supportsTerminalZoom])
    }

    // MARK: - AppCommandDispatcher

    @MainActor

    @Test
    func test_dispatcher_definitions_registered() {
        // Act
        let dispatcher = AppCommandDispatcher.shared

        // Assert
        #expect(dispatcher.definitions.count == AppCommand.allCases.count)
        #expect(dispatcher.definition(for: .closeTab).command == .closeTab)
        #expect(dispatcher.definition(for: .closePane).command == .closePane)
        #expect(dispatcher.definition(for: .watchFolder).command == .watchFolder)
        #expect(dispatcher.definition(for: .toggleSidebar).command == .toggleSidebar)
    }

    @Test
    func test_toggleSidebar_isVisibleInCommandBar() {
        let definition = AppCommandDispatcher.shared.definition(for: .toggleSidebar)
        #expect(definition.surfacePolicy.exposes(.commandBar))
        #expect(definition.surfacePolicy == .exposed([.commandBar]))
        #expect(definition.targeting == .contextual)
    }

    @Test
    func test_dispatcher_registersDefinitionForEveryCommand() {
        let dispatcher = AppCommandDispatcher.shared

        for command in AppCommand.allCases {
            let definition = dispatcher.definition(for: command)
            #expect(definition.command == command)
        }
    }

    @Test
    func test_dispatcher_allCommandsHaveHelpText() throws {
        let dispatcher = AppCommandDispatcher.shared

        for command in AppCommand.allCases {
            let definition = dispatcher.definition(for: command)
            #expect(!definition.helpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @MainActor

    @Test
    func test_dispatcher_closeTab_hasCorrectKeyBinding() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        #expect(def.keyBinding?.key == "w")
        #expect(def.keyBinding?.modifiers == [.command])
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forTab_includesExpected() {
        // Act
        let tabCommands = AppCommandDispatcher.shared.commands(for: .tab)

        // Assert
        let commandNames = tabCommands.map(\.command)
        #expect(commandNames.contains(.closeTab))
        #expect(commandNames.contains(.breakUpTab))
        #expect(commandNames.contains(.movePaneToTab))
        #expect(commandNames.contains(.equalizePanes))
        #expect(
            AppCommand.equalizePanes.definition.targeting
                == .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                )
        )
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forPane_includesExpected() {
        // Act
        let paneCommands = AppCommandDispatcher.shared.commands(for: .pane)

        // Assert
        let commandNames = paneCommands.map(\.command)
        #expect(commandNames.contains(.closePane))
        #expect(commandNames.contains(.extractPaneToTab))
        #expect(commandNames.contains(.movePaneToTab))
    }

    @MainActor

    @Test
    func test_arrangementShortcutDefinitions_useTabGroupAndShortcuts() {
        let show = AppCommandDispatcher.shared.definition(for: .switchArrangement)
        let previous = AppCommandDispatcher.shared.definition(for: .previousArrangement)
        let next = AppCommandDispatcher.shared.definition(for: .nextArrangement)

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
    func test_ordinalShortcutDefinitions_useCommandForTabsAndOptionForPanes() {
        let firstTab = AppCommandDispatcher.shared.definition(for: .selectTab1)
        let ninthTab = AppCommandDispatcher.shared.definition(for: .selectTab9)
        let firstPane = AppCommandDispatcher.shared.definition(for: .focusPane1)
        let ninthPane = AppCommandDispatcher.shared.definition(for: .focusPane9)

        #expect(firstTab.shortcut == .selectTab1)
        #expect(firstTab.keyBinding?.key == "1")
        #expect(firstTab.keyBinding?.modifiers == [.command])
        #expect(ninthTab.shortcut == .selectTab9)
        #expect(ninthTab.keyBinding?.key == "9")
        #expect(ninthTab.keyBinding?.modifiers == [.command])

        #expect(firstPane.shortcut == .focusPane1)
        #expect(firstPane.keyBinding?.key == "1")
        #expect(firstPane.keyBinding?.modifiers == [.option])
        #expect(ninthPane.shortcut == .focusPane9)
        #expect(ninthPane.keyBinding?.key == "9")
        #expect(ninthPane.keyBinding?.modifiers == [.option])
    }

    @MainActor

    @Test
    func test_terminalScrollAndPromptDefinitions_useTerminalGroupAndShortcuts() {
        let scroll = AppCommandDispatcher.shared.definition(for: .scrollToBottom)
        let pageUp = AppCommandDispatcher.shared.definition(for: .scrollPageUp)
        let previousPrompt = AppCommandDispatcher.shared.definition(for: .jumpToPreviousPrompt)
        let nextPrompt = AppCommandDispatcher.shared.definition(for: .jumpToNextPrompt)

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
        let sidebarInbox = AppCommandDispatcher.shared.definition(for: .showInboxNotifications)
        let toggleInboxSort = AppCommandDispatcher.shared.definition(for: .toggleInboxNotificationSort)
        let clearReadInbox = AppCommandDispatcher.shared.definition(for: .clearReadInboxNotifications)
        let clearAllInbox = AppCommandDispatcher.shared.definition(for: .clearAllInboxNotifications)
        let paneInbox = AppCommandDispatcher.shared.definition(for: .showPaneInboxNotifications)
        let clearPaneInbox = AppCommandDispatcher.shared.definition(for: .clearPaneInboxNotifications)
        let worktreeSidebar = AppCommandDispatcher.shared.definition(for: .showWorktreeSidebar)

        #expect(sidebarInbox.shortcut == .showInboxNotifications)
        #expect(sidebarInbox.surfacePolicy.exposes(.commandBar))
        #expect(sidebarInbox.surfacePolicy == .exposed([.commandBar, .toolbar(.app)]))
        #expect(sidebarInbox.targeting == .contextual)
        #expect(toggleInboxSort.label == "Toggle Inbox Sort Order")
        #expect(toggleInboxSort.shortcut == nil)
        #expect(toggleInboxSort.icon == .system(.arrowUpArrowDown))
        #expect(toggleInboxSort.commandBarGroupName == "Inbox")
        #expect(toggleInboxSort.commandBarGroupPriority != sidebarInbox.commandBarGroupPriority)
        #expect(toggleInboxSort.surfacePolicy.exposes(.commandBar))
        #expect(toggleInboxSort.surfacePolicy == .exposed([.commandBar, .inlineControl]))
        #expect(toggleInboxSort.targeting == .contextual)
        #expect(clearReadInbox.label == "Clear Read Inbox Notifications")
        #expect(clearReadInbox.shortcut == nil)
        #expect(clearReadInbox.icon == .system(.deleteLeft))
        #expect(clearReadInbox.commandBarGroupName == "Inbox")
        #expect(clearReadInbox.commandBarGroupPriority == toggleInboxSort.commandBarGroupPriority)
        #expect(clearReadInbox.surfacePolicy.exposes(.commandBar))
        #expect(clearReadInbox.surfacePolicy == .exposed([.commandBar, .inlineControl]))
        #expect(clearReadInbox.targeting == .contextual)
        #expect(clearAllInbox.label == "Clear All Inbox Notifications")
        #expect(clearAllInbox.shortcut == nil)
        #expect(clearAllInbox.icon == .system(.deleteLeft))
        #expect(clearAllInbox.commandBarGroupName == "Inbox")
        #expect(clearAllInbox.commandBarGroupPriority == toggleInboxSort.commandBarGroupPriority)
        #expect(clearAllInbox.surfacePolicy.exposes(.commandBar))
        #expect(clearAllInbox.surfacePolicy == .exposed([.commandBar, .inlineControl]))
        #expect(clearAllInbox.targeting == .contextual)
        #expect(paneInbox.shortcut == .showPaneInboxNotifications)
        #expect(paneInbox.surfacePolicy.exposes(.commandBar))
        #expect(
            paneInbox.surfacePolicy
                == .exposed([.commandBar, .toolbar(.pane), .toolbar(.terminalZoom)])
        )
        #expect(
            paneInbox.targeting
                == .contextualAndTargeted(
                    [.pane, .floatingTerminal],
                    preferredInvocation: .contextual
                )
        )
        #expect(paneInbox.visibleWhen == [.hasActivePane])
        #expect(paneInbox.commandBarGroupName == "Pane")
        #expect(clearPaneInbox.label == "Clear Pane Inbox")
        #expect(clearPaneInbox.shortcut == nil)
        #expect(clearPaneInbox.icon == .system(.deleteLeft))
        #expect(clearPaneInbox.helpText.contains("Clear notifications"))
        #expect(clearPaneInbox.commandBarGroupName == "Pane")
        #expect(clearPaneInbox.commandBarGroupPriority == paneInbox.commandBarGroupPriority)
        #expect(clearPaneInbox.surfacePolicy == .exposed([.commandBar, .inlineControl]))
        #expect(
            clearPaneInbox.targeting
                == .contextualAndTargeted(
                    [.pane, .floatingTerminal],
                    preferredInvocation: .contextual
                )
        )
        #expect(worktreeSidebar.shortcut == .showWorktreeSidebar)
        #expect(worktreeSidebar.surfacePolicy.exposes(.commandBar))
        #expect(worktreeSidebar.surfacePolicy == .exposed([.commandBar, .toolbar(.app)]))
        #expect(worktreeSidebar.targeting == .contextual)
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forRepo_includesExpected() {
        // Act
        let repoCommands = AppCommandDispatcher.shared.commands(for: .repo)

        // Assert
        let commandNames = repoCommands.map(\.command)
        #expect(commandNames.contains(.addRepoFavorite))
        #expect(commandNames.contains(.removeRepoFavorite))
        #expect(commandNames.contains(.removeRepo))
        #expect(!commandNames.contains(.openWorktree))
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_withoutHandler_doesNotCrash() async throws {
        // Arrange
        let dispatcher = AppCommandDispatcher.shared

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

    @Test
    func test_dispatcher_dispatchRequest_routesTypedArgumentsToAppRouter() async throws {
        let dispatcher = AppCommandDispatcher.shared
        let appRouter = MockAppCommandRouter()
        appRouter.requestCommands = [.setRepoSidebarVisibilityMode]
        appRouter.parameterlessCanExecuteResult = false
        let request = AppCommandExecutionRequest(
            command: .setRepoSidebarVisibilityMode,
            arguments: .repoSidebarVisibilityMode(.favoritesOnly)
        )

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = nil
                dispatcher.appCommandRouter = appRouter
            },
            body: {
                let outcome = dispatcher.dispatch(request)

                #expect(outcome == .applied)
                #expect(appRouter.handledRequests == [request])
            }
        )
    }

    @MainActor

    @Test
    func test_dispatcher_canDispatch_withoutHandler_returnsFalse() async throws {
        // Arrange
        let dispatcher = AppCommandDispatcher.shared

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
        let dispatcher = AppCommandDispatcher.shared
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
        let dispatcher = AppCommandDispatcher.shared
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
        let dispatcher = AppCommandDispatcher.shared
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
        let dispatcher = AppCommandDispatcher.shared
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
        let dispatcher = AppCommandDispatcher.shared
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
        let dispatcher = AppCommandDispatcher.shared
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
        try await withAsyncTestCoreAtoms { _ in
            let dispatcher = AppCommandDispatcher.shared
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
    func test_dispatcher_dispatchMovePaneToTab_rechecksExactSourcePaneCapability() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let dispatcher = AppCommandDispatcher.shared
            let handler = MockCommandHandler()
            handler.canExecuteResult = true
            handler.targetedCanExecuteResult = false
            atom(\.managementLayer).deactivate()

            try await withIsolatedCommandDispatcher(
                configure: {
                    dispatcher.handler = handler
                    dispatcher.appCommandRouter = nil
                },
                body: {
                    atom(\.managementLayer).toggle()
                    defer { atom(\.managementLayer).deactivate() }

                    dispatcher.dispatchMovePaneToTab(
                        sourcePaneId: UUID(),
                        sourceTabId: UUID(),
                        targetTabId: UUID()
                    )

                    #expect(handler.movePaneRequests.isEmpty)
                }
            )
        }
    }

    @MainActor

    @Test
    func test_dispatcher_cannotDispatch_whenHandlerReturnsFalse() async throws {
        // Arrange
        let dispatcher = AppCommandDispatcher.shared
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
        let def = AppCommandDispatcher.shared.definition(for: .closePane)

        // Assert
        #expect(def.requiresManagementLayer)
    }

    @MainActor

    @Test
    func test_dispatcher_movePaneToTab_requiresManagementLayer() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .movePaneToTab)

        // Assert
        #expect(def.requiresManagementLayer)
        #expect(def.surfacePolicy == .exposed([.commandBar, .contextMenu, .inlineControl]))
        #expect(def.targeting == .targeted([.pane, .tab]))
    }

    @MainActor

    @Test
    func test_dispatcher_closeTab_doesNotRequireManagementLayer() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        #expect(!def.requiresManagementLayer)
    }

    @MainActor

    @Test
    func test_dispatcher_managementRequiredCommand_blockedWhenInactive() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let dispatcher = AppCommandDispatcher.shared
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
    func test_dispatcher_managementRequiredCommands_useAcceptedInvocationWhenActive() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let dispatcher = AppCommandDispatcher.shared
            let handler = MockCommandHandler()
            let paneId = UUID()
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
                    #expect(!dispatcher.canDispatch(.movePaneToTab))
                    #expect(
                        dispatcher.canDispatch(
                            .movePaneToTab,
                            target: paneId,
                            targetType: .pane
                        )
                    )
                }
            )
        }
    }

}
