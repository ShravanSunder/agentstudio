import Foundation
import Testing

@Suite("WelcomeLauncherArchitectureTests")
struct WelcomeLauncherArchitectureTests {
    @Test("file menu keeps real new tab command")
    func fileMenuKeepsRealNewTabCommand() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"),
            encoding: .utf8
        )

        #expect(source.contains("fileMenu.addItem(menuItem(command: .newTab, action: #selector(newTab)))"))
    }

    @Test("launcher keeps Watch Folder as a text shortcut row")
    func launcherKeepsWatchFolderAsTextShortcutRow() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("keyImage: \"folder.badge.plus\""))
        #expect(source.contains("title: \"Watch Folder\""))
        #expect(source.contains("subtitle: \"Scan and keep watching a folder for repos.\""))
        #expect(source.contains("action: { AppCommandDispatcher.shared.dispatch(.watchFolder) }"))
        #expect(!source.contains("private func launcherIconShortcutButton("))
    }

    @Test("launcher command rows derive labels and shortcuts from command specs")
    func launcherCommandRowsDeriveFromCommandSpecs() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("let quickFindDefinition = AppCommand.showCommandBarEverything.definition"))
        #expect(source.contains("let newTabOrWorktreeDefinition = AppCommand.showCommandBarRepos.definition"))
        #expect(source.contains("key: quickFindDefinition.keyBinding?.displayString"))
        #expect(source.contains("title: quickFindDefinition.label"))
        #expect(source.contains("action: { AppCommandDispatcher.shared.dispatch(quickFindDefinition.command) }"))
        #expect(source.contains("key: newTabOrWorktreeDefinition.keyBinding?.displayString"))
        #expect(source.contains("title: newTabOrWorktreeDefinition.label"))
        #expect(source.contains("action: { AppCommandDispatcher.shared.dispatch(newTabOrWorktreeDefinition.command) }"))
        #expect(!source.contains("title: \"Command palette\""))
    }

    @Test("main window does not restore product toolbar actions")
    func mainWindowDoesNotRestoreProductToolbarActions() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Windows/MainWindowController.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("setupToolbar()"))
        #expect(!source.contains("NSToolbar(identifier:"))
        #expect(!source.contains("commandToolbarButtonItem(for: .watchFolder"))
        #expect(!source.contains("extension MainWindowController: NSToolbarDelegate"))
    }
}
