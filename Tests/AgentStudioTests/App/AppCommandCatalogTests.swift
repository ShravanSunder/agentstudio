import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class AppCommandCatalogTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    // MARK: - Sidebar Commands

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_registered() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def.label == "Filter Sidebar")
        #expect(def.icon == .system(.magnifyingglass))
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_hasCorrectKeyBinding() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def.keyBinding?.key == "f")
        #expect(def.keyBinding?.modifiers.contains(.command) ?? false)
        #expect(!(def.keyBinding?.modifiers.contains(.shift) ?? false))
    }

    @MainActor

    @Test
    func test_dispatcher_openNewTerminalInTab_registered() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        #expect(def.label == "Open Terminal in New Tab")
        #expect(def.icon == .system(.terminalFill))
        #expect(def.helpText == "Open a worktree in a fresh terminal tab")
    }

    @MainActor

    @Test
    func test_dispatcher_openNewTerminalInTab_appliesToWorktree() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .openNewTerminalInTab)

        // Assert
        #expect(def.appliesTo.contains(.worktree))
    }

    @MainActor

    @Test
    func test_dispatcher_commands_forWorktree_includesOpenNewTerminal() {
        // Act
        let worktreeCommands = AppCommandDispatcher.shared.commands(for: .worktree)

        // Assert
        let commandNames = worktreeCommands.map(\.command)
        #expect(commandNames.contains(.openNewTerminalInTab))
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_doesNotRequireManagementLayer() {
        // Act
        let def = AppCommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(!def.requiresManagementLayer)
    }

    @MainActor

    @Test
    func test_dispatcher_filterSidebar_noAppliesTo() {
        // Act — filterSidebar is a global command, not tied to an item type
        let def = AppCommandDispatcher.shared.definition(for: .filterSidebar)

        // Assert
        #expect(def.appliesTo.isEmpty)
    }

    // MARK: - Webview Commands

    @MainActor

    @Test
    func test_dispatcher_openWebview_registered() {
        let def = AppCommandDispatcher.shared.definition(for: .openWebview)
        #expect(def.label == "Open New Webview Tab")
        #expect(def.icon == .system(.globe))
    }

    @MainActor

    @Test
    func test_dispatcher_openWebview_noKeyBinding() {
        let def = AppCommandDispatcher.shared.definition(for: .openWebview)
        #expect(def.keyBinding == nil)
    }

    @MainActor

    @Test
    func test_dispatcher_showBridgeReview_registered() {
        let def = AppCommandDispatcher.shared.definition(for: .showBridgeReview)
        #expect(def.label == "Review")
        #expect(def.icon == .system(.rectangleSplit2x1))
        #expect(def.commandBarGroupName == "Bridge")
    }

    @MainActor

    @Test
    func test_dispatcher_showBridgeFiles_registered() {
        let def = AppCommandDispatcher.shared.definition(for: .showBridgeFiles)
        #expect(def.label == "Files")
        #expect(def.icon == .system(.folder))
        #expect(def.commandBarGroupName == "Bridge")
    }

    @MainActor

    @Test
    func test_dispatcher_openBridgeReviewInNewTab_registered() {
        let def = AppCommandDispatcher.shared.definition(for: .openBridgeReviewInNewTab)
        #expect(def.label == "Open Review in New Tab")
        #expect(def.icon == .system(.rectangleSplit2x1))
        #expect(def.commandBarGroupName == "Bridge")
    }

    @MainActor

    @Test
    func test_dispatcher_openBridgeFilesInNewTab_registered() {
        let def = AppCommandDispatcher.shared.definition(for: .openBridgeFilesInNewTab)
        #expect(def.label == "Open Files in New Tab")
        #expect(def.icon == .system(.folder))
        #expect(def.commandBarGroupName == "Bridge")
    }

    @MainActor

    @Test
    func test_dispatcher_bridgeCommands_haveNoKeyBindings() {
        #expect(AppCommand.showBridgeReview.definition.keyBinding == nil)
        #expect(AppCommand.showBridgeFiles.definition.keyBinding == nil)
        #expect(AppCommand.openBridgeReviewInNewTab.definition.keyBinding == nil)
        #expect(AppCommand.openBridgeFilesInNewTab.definition.keyBinding == nil)
    }

    @MainActor

    @Test
    func test_dispatcher_bridgeCommands_applyToWorktrees() {
        #expect(AppCommand.showBridgeReview.definition.appliesTo.contains(.worktree))
        #expect(AppCommand.showBridgeFiles.definition.appliesTo.contains(.worktree))
        #expect(AppCommand.openBridgeReviewInNewTab.definition.appliesTo.contains(.worktree))
        #expect(AppCommand.openBridgeFilesInNewTab.definition.appliesTo.contains(.worktree))
    }

    @MainActor

    @Test
    func test_dispatcher_signInGitHub_registered() {
        let def = AppCommandDispatcher.shared.definition(for: .signInGitHub)
        #expect(def.label == "Sign in to GitHub")
        #expect(def.icon == .system(.personBadgeKey))
    }

    @MainActor

    @Test
    func test_dispatcher_signInGoogle_registered() {
        let def = AppCommandDispatcher.shared.definition(for: .signInGoogle)
        #expect(def.label == "Sign in to Google")
        #expect(def.icon == .system(.personBadgeKey))
    }

    @MainActor

    @Test
    func test_dispatcher_signIn_noKeyBindings() {
        // Sign-in commands are invoked from command bar, no global shortcuts
        #expect(AppCommandDispatcher.shared.definition(for: .signInGitHub).keyBinding == nil)
        #expect(AppCommandDispatcher.shared.definition(for: .signInGoogle).keyBinding == nil)
    }
}
