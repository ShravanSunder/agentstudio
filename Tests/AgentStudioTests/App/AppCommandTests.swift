import XCTest
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

final class AppCommandTests: XCTestCase {

    // MARK: - AppCommand Enum

    func test_appCommand_allCases_notEmpty() {
        // Assert
        XCTAssertFalse(AppCommand.allCases.isEmpty)
    }

    func test_appCommand_rawValues_unique() {
        // Arrange
        let rawValues = AppCommand.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)

        // Assert
        XCTAssertEqual(rawValues.count, uniqueValues.count, "All raw values should be unique")
    }

    // MARK: - SearchItemType

    func test_searchItemType_allCases_containsExpectedTypes() {
        // Assert
        XCTAssertTrue(SearchItemType.allCases.contains(.repo))
        XCTAssertTrue(SearchItemType.allCases.contains(.worktree))
        XCTAssertTrue(SearchItemType.allCases.contains(.tab))
        XCTAssertTrue(SearchItemType.allCases.contains(.pane))
        XCTAssertTrue(SearchItemType.allCases.contains(.floatingTerminal))
    }

    // MARK: - KeyBinding

    func test_keyBinding_codable_roundTrip() throws {
        // Arrange
        let binding = KeyBinding(key: "w", modifiers: [.command])

        // Act
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)

        // Assert
        XCTAssertEqual(decoded.key, "w")
        XCTAssertEqual(decoded.modifiers, [.command])
    }

    func test_keyBinding_codable_multipleModifiers_roundTrip() throws {
        // Arrange
        let binding = KeyBinding(key: "O", modifiers: [.command, .shift])

        // Act
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)

        // Assert
        XCTAssertEqual(decoded.key, "O")
        XCTAssertTrue(decoded.modifiers.contains(.command))
        XCTAssertTrue(decoded.modifiers.contains(.shift))
    }

    func test_keyBinding_hashable_sameBindings_equal() {
        // Arrange
        let b1 = KeyBinding(key: "w", modifiers: [.command])
        let b2 = KeyBinding(key: "w", modifiers: [.command])

        // Assert
        XCTAssertEqual(b1, b2)
    }

    func test_keyBinding_hashable_differentKeys_notEqual() {
        // Arrange
        let b1 = KeyBinding(key: "w", modifiers: [.command])
        let b2 = KeyBinding(key: "q", modifiers: [.command])

        // Assert
        XCTAssertNotEqual(b1, b2)
    }

    // MARK: - CommandDefinition

    func test_commandDefinition_init_defaults() {
        // Act
        let def = CommandDefinition(command: .closeTab, label: "Close Tab")

        // Assert
        XCTAssertEqual(def.command, .closeTab)
        XCTAssertEqual(def.label, "Close Tab")
        XCTAssertNil(def.keyBinding)
        XCTAssertNil(def.icon)
        XCTAssertTrue(def.appliesTo.isEmpty)
        XCTAssertFalse(def.requiresManagementMode)
    }

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
        XCTAssertEqual(def.command, .closePane)
        XCTAssertNotNil(def.keyBinding)
        XCTAssertEqual(def.icon, "xmark")
        XCTAssertTrue(def.appliesTo.contains(.pane))
        XCTAssertTrue(def.appliesTo.contains(.floatingTerminal))
        XCTAssertTrue(def.requiresManagementMode)
    }

    // MARK: - CommandDispatcher

    @MainActor
    func test_dispatcher_definitions_registered() {
        // Act
        let dispatcher = CommandDispatcher.shared

        // Assert
        XCTAssertNotNil(dispatcher.definition(for: .closeTab))
        XCTAssertNotNil(dispatcher.definition(for: .closePane))
        XCTAssertNotNil(dispatcher.definition(for: .addRepo))
        XCTAssertNotNil(dispatcher.definition(for: .toggleSidebar))
    }

    @MainActor
    func test_dispatcher_closeTab_hasCorrectKeyBinding() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        XCTAssertEqual(def?.keyBinding?.key, "w")
        XCTAssertEqual(def?.keyBinding?.modifiers, [.command])
    }

    @MainActor
    func test_dispatcher_commands_forTab_includesExpected() {
        // Act
        let tabCommands = CommandDispatcher.shared.commands(for: .tab)

        // Assert
        let commandNames = tabCommands.map(\.command)
        XCTAssertTrue(commandNames.contains(.closeTab))
        XCTAssertTrue(commandNames.contains(.breakUpTab))
        XCTAssertTrue(commandNames.contains(.equalizePanes))
    }

    @MainActor
    func test_dispatcher_commands_forPane_includesExpected() {
        // Act
        let paneCommands = CommandDispatcher.shared.commands(for: .pane)

        // Assert
        let commandNames = paneCommands.map(\.command)
        XCTAssertTrue(commandNames.contains(.closePane))
        XCTAssertTrue(commandNames.contains(.extractPaneToTab))
    }

    @MainActor
    func test_dispatcher_commands_forRepo_includesExpected() {
        // Act
        let repoCommands = CommandDispatcher.shared.commands(for: .repo)

        // Assert
        let commandNames = repoCommands.map(\.command)
        XCTAssertTrue(commandNames.contains(.addRepo))
        XCTAssertTrue(commandNames.contains(.removeRepo))
        XCTAssertTrue(commandNames.contains(.refreshWorktrees))
    }

    @MainActor
    func test_dispatcher_dispatch_withoutHandler_doesNotCrash() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        dispatcher.handler = nil

        // Act (should not crash)
        dispatcher.dispatch(.closeTab)
    }

    @MainActor
    func test_dispatcher_canDispatch_withoutHandler_returnsFalse() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        dispatcher.handler = nil

        // Act
        let result = dispatcher.canDispatch(.closeTab)

        // Assert
        XCTAssertFalse(result)
    }

    @MainActor
    func test_dispatcher_dispatch_callsHandler() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        dispatcher.handler = handler

        // Act
        dispatcher.dispatch(.closeTab)

        // Assert
        XCTAssertEqual(handler.executedCommands.count, 1)
        XCTAssertEqual(handler.executedCommands[0].0, .closeTab)
        XCTAssertNil(handler.executedCommands[0].1) // no target

        // Cleanup
        dispatcher.handler = nil
    }

    @MainActor
    func test_dispatcher_dispatch_targeted_callsHandler() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        dispatcher.handler = handler
        let targetId = UUID()

        // Act
        dispatcher.dispatch(.closeTab, target: targetId, targetType: .tab)

        // Assert
        XCTAssertEqual(handler.executedCommands.count, 1)
        XCTAssertEqual(handler.executedCommands[0].0, .closeTab)
        XCTAssertEqual(handler.executedCommands[0].1, targetId)
        XCTAssertEqual(handler.executedCommands[0].2, .tab)

        // Cleanup
        dispatcher.handler = nil
    }

    @MainActor
    func test_dispatcher_cannotDispatch_whenHandlerReturnsFalse() {
        // Arrange
        let dispatcher = CommandDispatcher.shared
        let handler = MockCommandHandler()
        handler.canExecuteResult = false
        dispatcher.handler = handler

        // Act
        dispatcher.dispatch(.closeTab)

        // Assert — command should not have been executed
        XCTAssertTrue(handler.executedCommands.isEmpty)

        // Cleanup
        dispatcher.handler = nil
    }

    @MainActor
    func test_dispatcher_closePane_requiresManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closePane)

        // Assert
        XCTAssertTrue(def?.requiresManagementMode ?? false)
    }

    @MainActor
    func test_dispatcher_closeTab_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .closeTab)

        // Assert
        XCTAssertFalse(def?.requiresManagementMode ?? true)
    }

    // MARK: - Sidebar Commands

    @MainActor
    func test_dispatcher_filterSidebar_registered() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.label, "Filter Sidebar")
        XCTAssertEqual(def?.icon, "magnifyingglass")
    }

    @MainActor
    func test_dispatcher_filterSidebar_hasCorrectKeyBinding() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        XCTAssertEqual(def?.keyBinding?.key, "f")
        XCTAssertTrue(def?.keyBinding?.modifiers.contains(.command) ?? false)
        XCTAssertTrue(def?.keyBinding?.modifiers.contains(.shift) ?? false)
    }

    @MainActor
    func test_dispatcher_openNewTerminalInTab_registered() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.label, "Open New Terminal in Tab")
        XCTAssertEqual(def?.icon, "terminal.fill")
    }

    @MainActor
    func test_dispatcher_openNewTerminalInTab_appliesToWorktree() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        XCTAssertTrue(def?.appliesTo.contains(.worktree) ?? false)
    }

    @MainActor
    func test_dispatcher_commands_forWorktree_includesOpenNewTerminal() {
        // Act
        let worktreeCommands = CommandDispatcher.shared.commands(for: .worktree)

        // Assert
        let commandNames = worktreeCommands.map(\.command)
        XCTAssertTrue(commandNames.contains(.openNewTerminalInTab))
    }

    @MainActor
    func test_dispatcher_filterSidebar_doesNotRequireManagementMode() {
        // Act
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        XCTAssertFalse(def?.requiresManagementMode ?? true)
    }

    @MainActor
    func test_dispatcher_filterSidebar_noAppliesTo() {
        // Act — filterSidebar is a global command, not tied to an item type
        let def = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        XCTAssertTrue(def?.appliesTo.isEmpty ?? false)
    }

    // MARK: - Webview Commands

    @MainActor
    func test_dispatcher_openWebview_registered() {
        let def = CommandDispatcher.shared.definition(for: .openWebview)
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.label, "Open URL")
        XCTAssertEqual(def?.icon, "globe")
    }

    @MainActor
    func test_dispatcher_openWebview_hasCorrectKeyBinding() {
        let def = CommandDispatcher.shared.definition(for: .openWebview)
        XCTAssertEqual(def?.keyBinding?.key, "l")
        XCTAssertTrue(def?.keyBinding?.modifiers.contains(.command) ?? false)
        XCTAssertTrue(def?.keyBinding?.modifiers.contains(.shift) ?? false)
    }

    @MainActor
    func test_dispatcher_signInGitHub_registered() {
        let def = CommandDispatcher.shared.definition(for: .signInGitHub)
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.label, "Sign in to GitHub")
        XCTAssertEqual(def?.icon, "person.badge.key")
    }

    @MainActor
    func test_dispatcher_signInGoogle_registered() {
        let def = CommandDispatcher.shared.definition(for: .signInGoogle)
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.label, "Sign in to Google")
        XCTAssertEqual(def?.icon, "person.badge.key")
    }

    @MainActor
    func test_dispatcher_signIn_noKeyBindings() {
        // Sign-in commands are invoked from command bar, no global shortcuts
        XCTAssertNil(CommandDispatcher.shared.definition(for: .signInGitHub)?.keyBinding)
        XCTAssertNil(CommandDispatcher.shared.definition(for: .signInGoogle)?.keyBinding)
    }
}
