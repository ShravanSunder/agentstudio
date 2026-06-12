import Foundation
import Testing

@Suite("RepositoryTopologyHotPathArchitectureTests")
struct RepositoryTopologyHotPathArchitectureTests {
    @Test("repoAndWorktree lookup uses the precomputed path index")
    func repoAndWorktreeLookupUsesPrecomputedPathIndex() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift"
            ),
            encoding: .utf8
        )

        let body = try #require(
            source.slice(
                from: "func repoAndWorktree(containing cwd: URL?)",
                to: "@discardableResult\n    func addRepo"
            )
        )

        #expect(body.contains("worktreePathIndex"))
        #expect(!body.contains("repos.flatMap"))
        #expect(body.components(separatedBy: ".standardizedFileURL").count - 1 == 1)
    }

    @Test("pane management context reuses one repo/worktree resolution")
    func paneManagementContextReusesOneRepoWorktreeResolution() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift"
            ),
            encoding: .utf8
        )

        let projectBody = try #require(
            source.slice(from: "static func project(", to: "private static func projectIdentityRows")
        )

        #expect(projectBody.components(separatedBy: "repoAndWorktree(containing:").count - 1 == 1)
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
