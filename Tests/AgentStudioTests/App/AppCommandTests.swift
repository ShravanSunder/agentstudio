import Foundation
import Testing

@testable import AgentStudio

// MARK: - Mock Command Handler

final class MockCommandHandler: CommandHandler {
    var executedCommands: [(AppCommand, UUID?, SearchItemType?)] = []
    var canExecuteResult: Bool = true

    func execute(_ command: AppCommand) {
        executedCommands.append((command, nil, nil))
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        executedCommands.append((command, target, targetType))
    }

    func canExecute(_ command: AppCommand) -> Bool {
        canExecuteResult
    }
}

// MARK: - AppCommand Tests

@Suite(.serialized)
final class AppCommandTests {

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

    // MARK: - CommandDefinition

    @Test
    func test_commandDefinition_init_defaults() {
        // Act
        let def = CommandDefinition(command: .closeTab, label: "Close Tab")

        // Assert
        #expect(def.command == .closeTab)
        #expect(def.label == "Close Tab")
        #expect(def.keyBinding == nil)
        #expect(def.icon == nil)
        #expect(def.appliesTo.isEmpty)
        #expect(!(def.requiresManagementMode))
    }

    @Test
    func test_commandDefinition_init_full() {
        // Act
        let def = CommandDefinition(
            command: .closePane,
            keyBinding: KeyBinding(key: "w", modifiers: [.command, .shift]),
            label: "Close Pane",
            icon: "xmark",
            appliesTo: [.pane, .floatingTerminal],
            requiresManagementMode: true
        )

        // Assert
        #expect(def.command == .closePane)
        #expect(def.keyBinding != nil)
        #expect(def.icon == "xmark")
        #expect(def.appliesTo.contains(.pane))
        #expect(def.appliesTo.contains(.floatingTerminal))
        #expect(def.requiresManagementMode)
    }

    // MARK: - CommandDispatcher

    @MainActor

    @Test
    func test_dispatcher_definitions_registered() {
        // Act
        let dispatcher = CommandDispatcher.shared

        // Assert
        #expect(dispatcher.definition(for: .closeTab) != nil)
        #expect(dispatcher.definition(for: .closePane) != nil)
        #expect(dispatcher.definition(for: .addRepo) != nil)
        #expect(dispatcher.definition(for: .toggleSidebar) != nil)
    }

    @MainActor

    @Test
    func test_dispatcher_closeTab_hasCorrectKeyBinding() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        #expect(def?.keyBinding?.key == "w")
        #expect(def?.keyBinding?.modifiers == [.command])
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
    func test_dispatcher_commands_forRepo_includesExpected() {
        // Act
        let repoCommands = CommandDispatcher.shared.commands(for: .repo)

        // Assert
        let commandNames = repoCommands.map(\.command)
        #expect(commandNames.contains(.addRepo))
        #expect(commandNames.contains(.removeRepo))
        #expect(commandNames.contains(.refreshWorktrees))
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_withoutHandler_doesNotCrash() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        dispatcher.handler = nil

        // Act (should not crash)
        dispatcher.dispatch(.closeTab)
    }

    @MainActor

    @Test
    func test_dispatcher_canDispatch_withoutHandler_returnsFalse() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        dispatcher.handler = nil

        // Act
        let result = dispatcher.canDispatch(.closeTab)

        // Assert
        #expect(!(result))
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_callsHandler() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        dispatcher.handler = handler

        // Act
        dispatcher.dispatch(.closeTab)

        // Assert
        #expect(handler.executedCommands.count == 1)
        #expect(handler.executedCommands[0].0 == .closeTab)
        #expect(handler.executedCommands[0].1 == nil)  // no target

        // Cleanup
        dispatcher.handler = nil
    }

    @MainActor

    @Test
    func test_dispatcher_dispatch_targeted_callsHandler() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        dispatcher.handler = handler
        let targetId = UUID()

        // Act
        dispatcher.dispatch(.closeTab, target: targetId, targetType: .tab)

        // Assert
        #expect(handler.executedCommands.count == 1)
        #expect(handler.executedCommands[0].0 == .closeTab)
        #expect(handler.executedCommands[0].1 == targetId)
        #expect(handler.executedCommands[0].2 == .tab)

        // Cleanup
        dispatcher.handler = nil
    }

    @MainActor

    @Test
    func test_dispatcher_cannotDispatch_whenHandlerReturnsFalse() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        handler.canExecuteResult = false
        dispatcher.handler = handler

        // Act
        dispatcher.dispatch(.closeTab)

        // Assert — command should not have been executed
        #expect(handler.executedCommands.isEmpty)

        // Cleanup
        dispatcher.handler = nil
    }

    @MainActor

    @Test
    func test_dispatcher_closePane_requiresManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closePane)

        // Assert
        #expect(def?.requiresManagementMode ?? false)
    }

    @MainActor

    @Test
    func test_dispatcher_movePaneToTab_requiresManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .movePaneToTab)

        // Assert
        #expect(def?.requiresManagementMode ?? false)
        #expect(def?.appliesTo.contains(.pane) ?? false)
    }

    @MainActor

    @Test
    func test_dispatcher_closeTab_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        #expect(!(def?.requiresManagementMode ?? true))
    }

    @MainActor

    @Test
    func test_dispatcher_managementRequiredCommand_blockedWhenInactive() {
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        dispatcher.handler = handler
        ManagementModeMonitor.shared.deactivate()
        defer {
            dispatcher.handler = nil
            ManagementModeMonitor.shared.deactivate()
        }

        #expect(!dispatcher.canDispatch(.closePane))
        #expect(!dispatcher.canDispatch(.movePaneToTab))
    }

    @MainActor

    @Test
    func test_dispatcher_managementRequiredCommand_allowedWhenActive() {
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        dispatcher.handler = handler
        ManagementModeMonitor.shared.deactivate()
        ManagementModeMonitor.shared.toggle()
        defer {
            dispatcher.handler = nil
            ManagementModeMonitor.shared.deactivate()
        }

        #expect(dispatcher.canDispatch(.closePane))
        #expect(dispatcher.canDispatch(.movePaneToTab))
    }

    // MARK: - Sidebar Commands

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_registered() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def != nil)
        #expect(def?.label == "Filter Sidebar")
        #expect(def?.icon == "magnifyingglass")
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_hasCorrectKeyBinding() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def?.keyBinding?.key == "f")
        #expect(def?.keyBinding?.modifiers.contains(.command) ?? false)
        #expect(def?.keyBinding?.modifiers.contains(.shift) ?? false)
    }

    @MainActor

    @Test
    func test_dispatcher_openNewTerminalInTab_registered() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        #expect(def != nil)
        #expect(def?.label == "Open New Terminal in Tab")
        #expect(def?.icon == "terminal.fill")
    }

    @MainActor

    @Test
    func test_dispatcher_openNewTerminalInTab_appliesToWorktree() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        #expect(def?.appliesTo.contains(.worktree) ?? false)
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
    func test_dispatcher_filterSidebar_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(!(def?.requiresManagementMode ?? true))
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_noAppliesTo() {
        // Act — filterSidebar is a global command, not tied to an item type
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def?.appliesTo.isEmpty ?? false)
    }

    // MARK: - Webview Commands

    @MainActor

    @Test
    func test_dispatcher_openWebview_registered() {
        let def = CommandDispatcher.shared.definition(for: .openWebview)
        #expect(def != nil)
        #expect(def?.label == "Open New Webview Tab")
        #expect(def?.icon == "globe")
    }

    @MainActor

    @Test
    func test_dispatcher_openWebview_noKeyBinding() {
        let def = CommandDispatcher.shared.definition(for: .openWebview)
        #expect(def?.keyBinding == nil)
    }

    @MainActor

    @Test
    func test_dispatcher_signInGitHub_registered() {
        let def = CommandDispatcher.shared.definition(for: .signInGitHub)
        #expect(def != nil)
        #expect(def?.label == "Sign in to GitHub")
        #expect(def?.icon == "person.badge.key")
    }

    @MainActor

    @Test
    func test_dispatcher_signInGoogle_registered() {
        let def = CommandDispatcher.shared.definition(for: .signInGoogle)
        #expect(def != nil)
        #expect(def?.label == "Sign in to Google")
        #expect(def?.icon == "person.badge.key")
    }

    @MainActor

    @Test
    func test_dispatcher_signIn_noKeyBindings() {
        // Sign-in commands are invoked from command bar, no global shortcuts
        #expect(CommandDispatcher.shared.definition(for: .signInGitHub)?.keyBinding == nil)
        #expect(CommandDispatcher.shared.definition(for: .signInGoogle)?.keyBinding == nil)
    }
}
