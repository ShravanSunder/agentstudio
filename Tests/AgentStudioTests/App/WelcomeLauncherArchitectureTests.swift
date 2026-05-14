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
        #expect(source.contains("action: { CommandDispatcher.shared.dispatch(.watchFolder) }"))
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
        #expect(source.contains("action: { CommandDispatcher.shared.dispatch(quickFindDefinition.command) }"))
        #expect(source.contains("key: newTabOrWorktreeDefinition.keyBinding?.displayString"))
        #expect(source.contains("title: newTabOrWorktreeDefinition.label"))
        #expect(source.contains("action: { CommandDispatcher.shared.dispatch(newTabOrWorktreeDefinition.command) }"))
        #expect(!source.contains("title: \"Command palette\""))
    }

    @Test("main toolbar includes a command-spec-backed Watch Folder button")
    func mainToolbarIncludesCommandSpecBackedWatchFolderButton() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Windows/MainWindowController.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains(".watchFolder"))
        #expect(source.contains("commandToolbarButtonItem(for: .watchFolder, action: #selector(watchFolderAction))"))
        #expect(source.contains("let definition = CommandDispatcher.shared.definition(for: command)"))
        #expect(source.contains("item.toolTip = definition.controlToolTip"))
        #expect(source.contains("string: \"  \" + definition.actionSpec.label"))
        #expect(!source.contains("\"Watch Folder\""))
    }
}
