import Foundation
import Testing

@Suite("Repo Explorer toolbar shortcuts")
struct RepoExplorerToolbarShortcutTests {
    @Test("toolbar command tooltips use the list shortcut gate for every command")
    func toolbarTooltipsUseGenericShortcutGate() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift",
            encoding: .utf8
        )
        let commandToggle = try #require(source.components(separatedBy: "private func commandToggle(").last)
        #expect(commandToggle.contains("shortcutTextOverride: sidebarShortcutDisplay(for: command)"))
        #expect(!commandToggle.contains("command == .togglePanesShowsDrawers"))
    }
}
