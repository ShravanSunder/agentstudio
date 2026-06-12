import Foundation
import Testing

@Suite("CommandBarHotPathArchitectureTests")
struct CommandBarHotPathArchitectureTests {
    @Test("worktree scopes batch presence before building rows")
    func worktreeScopesBatchPresenceBeforeBuildingRows() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift"
            ),
            encoding: .utf8
        )

        let repoScopeItems = try #require(
            source.slice(
                from: "static func repoScopeItems(store: WorkspaceStore)", to: "static func everythingWorktreeItems")
        )
        let everythingWorktreeItems = try #require(
            source.slice(
                from: "static func everythingWorktreeItems(store: WorkspaceStore)",
                to: "static func unifiedWorktreeItem")
        )

        #expect(repoScopeItems.contains("buildWorktreePresenceByWorktreeId(store: store)"))
        #expect(everythingWorktreeItems.contains("buildWorktreePresenceByWorktreeId(store: store)"))
        #expect(!everythingWorktreeItems.contains("buildWorktreePresence(worktree:"))
    }
}

extension String {
    fileprivate func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }
}
