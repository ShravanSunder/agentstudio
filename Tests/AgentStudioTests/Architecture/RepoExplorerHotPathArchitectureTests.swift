import Foundation
import Testing

@testable import AgentStudioTestSupport

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
        #expect(source.contains("RepoExplorerProjectionAdapter()"))
        #expect(!source.contains("private var sidebarProjection: SidebarProjection"))
        #expect(!source.contains("private var sidebarRowIndex: RepoExplorerRowIndex"))
        #expect(!source.contains("private func resolvedWorktreeContext("))
        #expect(!source.contains(".id(sidebarProjectionFingerprint)"))
    }

    @Test("projection requests are built only after observation admits a semantic input change")
    func projectionRequestsAreBuiltOnlyAfterObservationAdmission() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )

        #expect(!source.contains(".onChange(of: projectionRequestKey)"))
        #expect(source.contains("withObservationTracking"))
        #expect(source.contains("private func observeProjectionInputs("))
        #expect(source.contains("let inputRevision = withObservationTracking"))
        #expect(source.contains("projectionInputRevision"))
        #expect(!source.contains("let request = withObservationTracking"))
        #expect(
            source.contains(
                "let request = projectionRequest\n        let requestBuildDuration"
            )
        )
        let requestCapture = try #require(source.range(of: "let request = projectionRequest"))
        let captureTelemetry = try #require(
            source.range(
                of: "stage: \"capture_rebuild\"",
                range: requestCapture.upperBound..<source.endIndex
            )
        )
        let requestEquality = try #require(
            source.range(
                of: "Self.projectionRequestKey(for: cachedProjectionRequest) == requestKey",
                range: captureTelemetry.upperBound..<source.endIndex
            )
        )
        #expect(captureTelemetry.lowerBound < requestEquality.lowerBound)
        #expect(
            source.contains(
                """
                .onChange(of: debouncedQuery) { _, _ in
                            let clock = ContinuousClock()
                            let requestBuildStart = clock.now
                            let request = projectionRequest
                            refreshProjection(
                                request: request,
                                requestBuildDuration: requestBuildStart.duration(to: clock.now)
                            )
                        }
                """
            )
        )
        #expect(
            source.contains(
                """
                refreshProjection(
                            request: request,
                            requestBuildDuration: requestBuildDuration
                """
            )
        )
    }

    @Test("projection inputs exclude removed Repo Explorer visibility semantics")
    func projectionInputsExcludeRemovedRepoExplorerVisibilitySemantics() throws {
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
        let snapshotSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerSnapshot.swift"
            ),
            encoding: .utf8
        )
        let commandPresentationSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerCommandPresentation.swift"
            ),
            encoding: .utf8
        )

        #expect(repoExplorerViewHelperSource.contains("previous.snapshot.groupingMode != next.snapshot.groupingMode"))
        #expect(repoExplorerViewHelperSource.contains("previous.snapshot.sortOrder != next.snapshot.sortOrder"))
        for source in [
            repoExplorerViewSource,
            repoExplorerViewHelperSource,
            performanceMetricsSource,
            snapshotSource,
            commandPresentationSource,
        ] {
            #expect(!source.contains("RepoExplorerVisibilityMode"))
            #expect(!source.contains("visibilityMode"))
            #expect(!source.contains("setRepoSidebarVisibilityMode"))
        }
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

        #expect(repoExplorerViewSource.contains("let isFavorite = currentRepoFavoriteState("))
        #expect(repoExplorerViewSource.contains("isFavorite: isFavorite"))
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

    @Test("repo sidebar product controls route through App command composition")
    func repoSidebarProductControlsRouteThroughAppCommandComposition() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let featureSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let appCompositionSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift"),
            encoding: .utf8
        )

        #expect(!featureSource.contains("repoExplorerPrefs.setRepoVisibilityMode"))
        #expect(!featureSource.contains("RepoExplorerVisibilityButton"))
        #expect(!featureSource.contains("onSetVisibilityMode"))
        #expect(!featureSource.contains("repoExplorerPrefs.toggleSortOrder"))
        #expect(!featureSource.contains("repoExplorerPrefs.setGroupingMode(candidate)"))
        #expect(featureSource.contains("let nextSortOrder = repoExplorerPrefs.sortOrder.toggled"))
        #expect(featureSource.contains("onSetSortOrder(nextSortOrder)"))
        #expect(featureSource.contains("let command = groupingCommand(for: candidate)"))
        #expect(featureSource.contains("commandPresentation.command(command)?.isEnabled == true"))
        #expect(featureSource.contains("commandDispatcher.dispatch(command)"))
        #expect(!featureSource.contains("AppCommandDispatcher.shared"))
        #expect(appCompositionSource.contains("command: .setRepoSidebarSortOrder"))
        #expect(appCompositionSource.contains("arguments: .repoSidebarSortOrder(order)"))
        #expect(!appCompositionSource.contains("setRepoSidebarVisibilityMode"))
        #expect(!appCompositionSource.contains("repoSidebarVisibilityMode"))
    }

    @Test("Repo Explorer body consumes immutable command presentation without live capability reads")
    func repoExplorerBodyConsumesImmutableCommandPresentation() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let featureSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let presentationSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerCommandPresentation.swift"),
            encoding: .utf8
        )

        #expect(featureSource.contains("commandPresentationSnapshot"))
        #expect(!featureSource.contains("visibilityCommand"))
        #expect(!featureSource.contains("canSetSortOrder"))
        #expect(!presentationSource.contains("dispatcher.canDispatch"))
    }
}
