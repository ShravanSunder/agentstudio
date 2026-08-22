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
        #expect(source.contains("RepoExplorerProjectionAdapter("))
        #expect(!source.contains("private var sidebarProjection: SidebarProjection"))
        #expect(!source.contains("private var sidebarRowIndex: RepoExplorerRowIndex"))
        #expect(!source.contains("private func resolvedWorktreeContext("))
        #expect(!source.contains(".id(sidebarProjectionFingerprint)"))
    }

    @Test("projection adapter owns demand observation capture and deadlines")
    func projectionAdapterOwnsTheCompleteInputLifecycle() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let adapterSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionAdapter.swift"
            ),
            encoding: .utf8
        )
        let captureSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionInputCapture.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains(".onChange(of: projectionRequestKey)"))
        #expect(!source.contains("withObservationTracking"))
        #expect(!source.contains("private func observeProjectionInputs("))
        #expect(adapterSource.contains("withObservationTracking"))
        #expect(adapterSource.contains("func updateDemand("))
        #expect(adapterSource.contains("func suspendDemand()"))
        #expect(adapterSource.contains("RepoExplorerObservationRegistration"))
        #expect(adapterSource.contains("scheduleRecencyDeadline"))
        #expect(!source.contains("projectionInputRevision"))
        #expect(!source.contains("private var projectionRequest:"))
        #expect(!source.contains("private func startProjectionObservation"))
        #expect(!source.contains("private func captureProjectionInputs"))
        #expect(!source.contains("@State private var projectionGeneration"))
        #expect(!source.contains("@State private var cachedProjectionRequest"))
        #expect(!source.contains("@State private var recencyDeadlineTask"))
        #expect(!source.contains("let request = withObservationTracking"))
        #expect(captureSource.contains("repoCache.isPullRequestLoading(forRepository: repositoryID)"))
        #expect(captureSource.contains("repoCache.isPullRequestDataUnavailable(forRepository: repositoryID)"))
        #expect(!source.contains("repoCache.loadingPullRequestRepoIds"))
        #expect(!source.contains("repoCache.unavailablePullRequestRepoIds"))
        #expect(!source.contains("paneRecencyDisplayCadence"))
        #expect(!source.contains("while !Task.isCancelled"))
        #expect(adapterSource.contains("admitDelta("))
        #expect(adapterSource.contains("stage: \"capture_rebuild\""))
        #expect(source.contains(".onChange(of: debouncedQuery)"))
        #expect(source.contains("projectionAdapter.updateDemand("))
    }

    @Test("Repo Explorer capture consumes stored topology identity")
    func repoExplorerCaptureConsumesStoredTopologyIdentity() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let captureSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionInputCapture.swift"
            ),
            encoding: .utf8
        )
        let presentationSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Models/RepoPresentation.swift"),
            encoding: .utf8
        )
        let rowIndexSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerRowIndex.swift"
            ),
            encoding: .utf8
        )

        let sidebarReposBody = try #require(
            captureSource.repoExplorerSlice(
                from: "private func sidebarRepos() -> [RepoPresentationItem]",
                to: "func makeSidebarSnapshot("
            )
        )
        let repoInitializerBody = try #require(
            presentationSource.repoExplorerSlice(
                from: "package init(\n        repo: Repo,",
                to: "package struct RepoIdentityMetadata"
            )
        )

        #expect(sidebarReposBody.contains("repositoryStableKey(for:"))
        #expect(sidebarReposBody.contains("worktreeStableKeysByID"))
        #expect(!repoInitializerBody.contains("repo.stableKey"))
        #expect(!rowIndexSource.contains("worktree.stableKey"))
        for source in [sidebarReposBody, repoInitializerBody, rowIndexSource] {
            #expect(!source.contains("StableKey.fromPath"))
            #expect(!source.contains("resolvingSymlinksInPath"))
            #expect(!source.contains("FileManager"))
        }
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

    @Test("pane rows render only immutable worker projection values")
    func paneRowsRenderOnlyImmutableWorkerProjectionValues() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let rowSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift"
            ),
            encoding: .utf8
        )
        let helperSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+ProjectionHelpers.swift"
            ),
            encoding: .utf8
        )
        let workerSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift"
            ),
            encoding: .utf8
        )

        #expect(rowSource.contains("let row: RepoExplorerProjectedPaneRow"))
        #expect(!rowSource.contains("atom("))
        #expect(!helperSource.contains("atom(\\.paneDisplay)"))
        #expect(workerSource.contains("paneRowFactsByPaneId"))
        // The source contract proves projection stays off MainActor.
        // swiftlint:disable:next no_task_detached
        #expect(workerSource.contains("Task.detached(priority: .userInitiated)"))
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
        let viewSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )
        let commandToolbarSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift"
            ),
            encoding: .utf8
        )
        let featureSource = viewSource + commandToolbarSource
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
        #expect(featureSource.contains("let command = groupingCommand(for: groupingMode)"))
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

extension String {
    fileprivate func repoExplorerSlice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }
}
