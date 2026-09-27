import Foundation
import Testing

@testable import AgentStudioTestSupport

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

        let searchItems = try #require(
            source.slice(
                from: "static func searchableRepositoryAndWorktreeItems(",
                to: "static func unifiedWorktreeItem(")
        )

        #expect(searchItems.contains("locationsByWorktreeId: worktreeLocationsByWorktreeId(store: store)"))
        #expect(searchItems.contains("presenceByWorktreeId[worktree.id]"))
        #expect(!searchItems.contains("buildWorktreePresence(worktree:"))
    }

    @Test("view and controller consume CommandBarResultSession instead of independent pipelines")
    func viewAndControllerConsumeResultSession() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let viewSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift"
            ),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift"
            ),
            encoding: .utf8
        )

        #expect(viewSource.contains("CommandBarResultSession"))
        #expect(controllerSource.contains("CommandBarResultSession"))

        for source in [viewSource, controllerSource] {
            #expect(!source.contains("private var allItems"))
            #expect(!source.contains("private var filteredItems"))
            #expect(!source.contains("private var groups"))
            #expect(!source.contains("private var displayedItems"))
            #expect(!source.contains("private var selectedItem"))
        }
    }

    @Test("root projection uses prepared topology identity without filesystem derivation")
    func rootProjectionAvoidsFilesystemIdentityWork() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+RootProjection.swift"
            ),
            encoding: .utf8
        )
        let forbiddenCalls = [
            ".stableKey",
            "StableKey.fromPath",
            "resolvingSymlinksInPath",
            "FileManager",
            "contentsOfDirectory",
            "fileExists",
            "resourceValues",
        ]

        for forbiddenCall in forbiddenCalls {
            #expect(!source.contains(forbiddenCall))
        }
    }

    @Test("Quick Open projection does not resolve filesystem aliases on the main actor")
    func quickOpenProjectionAvoidsFilesystemAliasResolution() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+QuickOpen.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("resolvingSymlinksInPath"))
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
