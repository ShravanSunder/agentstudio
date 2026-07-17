import Foundation
import Testing

@Suite("RepoExplorerHotPathArchitectureTests")
struct RepoExplorerHotPathArchitectureTests {
    @Test("RepoExplorer model files are pure and do not read atoms")
    func repoExplorerModelFilesDoNotReadAtoms() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let modelsDirectory = projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/Models")
        let modelFiles = try FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }

        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerSnapshot.swift"))
        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerProjection.swift"))
        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerRowIndex.swift"))
        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerProjectionWorker.swift"))

        for file in modelFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("atom("), "\(file.lastPathComponent) must stay free of atom reads")
        }
    }

    @Test("RepoExplorerView renders from row index instead of walking groups per row")
    func repoExplorerViewRendersFromRowIndex() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("RepoExplorerRowIndex"))
        #expect(source.contains("RepoExplorerProjectionWorker()"))
        #expect(!source.contains("private var sidebarProjection: SidebarProjection"))
        #expect(!source.contains("private var sidebarRowIndex: RepoExplorerRowIndex"))
        #expect(!source.contains("private func resolvedWorktreeContext("))
        #expect(!source.contains(".id(sidebarProjectionFingerprint)"))
    }

    @Test("visibility mode changes stay in measured projection worker path")
    func visibilityModeChangesStayInMeasuredProjectionWorkerPath() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoExplorerViewSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let repoExplorerViewHelperSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+ProjectionHelpers.swift"
            ),
            encoding: .utf8
        )
        let performanceMetricsSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift"),
            encoding: .utf8
        )

        #expect(
            repoExplorerViewHelperSource.contains("previous.snapshot.visibilityMode != next.snapshot.visibilityMode"))
        #expect(!repoExplorerViewSource.contains(".onChange(of: repoExplorerPrefs.repoVisibilityMode)"))
        #expect(!repoExplorerViewSource.contains(#"refreshProjection(force: true, trigger: "visibility_mode")"#))
        #expect(repoExplorerViewHelperSource.contains("\"visibility_mode\""))
        #expect(performanceMetricsSource.contains("case visibilityMode = \"visibility_mode\""))
    }

    @Test("repo rows render from cached projection facts instead of recomputing all worktree status")
    func repoRowsRenderFromCachedProjectionFacts() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoExplorerViewSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let projectionWorkerSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift"),
            encoding: .utf8
        )

        #expect(!repoExplorerViewSource.contains("private var worktreeStatusById"))
        #expect(!repoExplorerViewSource.contains("private func branchName(for worktree: Worktree)"))
        #expect(repoExplorerViewSource.contains("cachedProjectionResult.branchStatusByWorktreeId"))
        #expect(repoExplorerViewSource.contains("cachedProjectionResult.branchNameByWorktreeId"))
        #expect(projectionWorkerSource.contains("branchStatusByWorktreeId"))
        #expect(projectionWorkerSource.contains("branchNameByWorktreeId"))
    }

    @Test("repo favorite rows read current topology state instead of projected entity copies")
    func repoFavoriteRowsReadCurrentTopologyState() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoExplorerViewSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )

        #expect(repoExplorerViewSource.contains("isFavorite: currentRepoFavoriteState("))
        #expect(
            repoExplorerViewSource.contains(
                "store.repositoryTopologyAtom.repo(repoId)?.isFavorite ?? projectedFallback"
            )
        )
        #expect(!repoExplorerViewSource.contains("isFavorite: resolvedWorktreeContext.repo.isFavorite"))
    }

    @Test("repo favorite mutations enter through targeted app commands")
    func repoFavoriteMutationsEnterThroughTargetedAppCommands() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoExplorerViewSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )

        #expect(!repoExplorerViewSource.contains("repositoryTopologyAtom.setRepoFavorite"))
        #expect(repoExplorerViewSource.contains(".addRepoFavorite"))
        #expect(repoExplorerViewSource.contains(".removeRepoFavorite"))
        #expect(repoExplorerViewSource.contains("targetType: .repo"))
    }

    @Test("repo sidebar product controls dispatch existing app commands")
    func repoSidebarProductControlsDispatchExistingAppCommands() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("repoExplorerPrefs.setRepoVisibilityMode"))
        #expect(!source.contains("repoExplorerPrefs.toggleSortOrder"))
        #expect(!source.contains("repoExplorerPrefs.setGroupingMode(candidate)"))
        #expect(source.contains("command: .setRepoSidebarVisibilityMode"))
        #expect(source.contains("command: .setRepoSidebarSortOrder"))
        #expect(source.contains("AppCommandDispatcher.shared.dispatch(groupingCommand(for: candidate))"))
    }
}
