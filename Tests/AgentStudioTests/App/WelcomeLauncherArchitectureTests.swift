import Foundation
import Testing

@testable import AgentStudioTestSupport

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
        #expect(source.contains("let watchFolderDefinition = AppCommand.watchFolder.definition"))
        #expect(source.contains("title: watchFolderDefinition.label"))
        #expect(!source.contains("title: \"Watch Folder\""))
        #expect(source.contains("subtitle: \"Scan and keep watching a folder for repos.\""))
        #expect(source.contains("let watchFolderPresentation = ShellTabBarCommandPresentation("))
        #expect(source.contains("surface: .inlineControl"))
        #expect(source.contains("action: watchFolderPresentation.perform"))
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
        #expect(source.contains("let quickFindPresentation = ShellTabBarCommandPresentation("))
        #expect(source.contains("action: quickFindPresentation.perform"))
        #expect(source.contains("key: newTabOrWorktreeDefinition.keyBinding?.displayString"))
        #expect(source.contains("title: newTabOrWorktreeDefinition.label"))
        #expect(source.contains("title: watchFolderDefinition.label"))
        #expect(source.contains("let repositoriesPresentation = ShellTabBarCommandPresentation("))
        #expect(source.contains("action: repositoriesPresentation.perform"))
        #expect(source.contains("isEnabled: quickFindPresentation.isEnabled"))
        #expect(source.contains("isEnabled: repositoriesPresentation.isEnabled"))
        #expect(!source.contains("title: \"Command palette\""))
    }

    @Test("top chrome includes a command-spec-backed Watch Folder button")
    func topChromeIncludesCommandSpecBackedWatchFolderButton() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("struct WatchFolderTabBarMenu: View"))
        #expect(source.contains("ShellTabBarCommandPresentation("))
        #expect(source.contains("command: .watchFolder"))
        #expect(source.contains("commandContext: ShellTabBarCommandContext.current()"))
        #expect(source.contains("presentation.perform()"))
        #expect(source.contains("guard dispatcher.canDispatch(command) else { return }"))
        #expect(source.contains("dispatcher.dispatch(command)"))
        #expect(source.contains("ChromeToolbarButtonLabel("))
        #expect(source.contains("symbolName: \"folder.badge.plus\""))
        #expect(source.contains(".help(presentation.controlToolTip)"))
        #expect(!source.contains("\"Watch Folder\""))
    }
}
