import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct WorkspaceBridgePaneRefreshIntegrationTests {
        init() {
            installTestCoreAtomsIfNeeded()
        }

        @Test("canonical workspace activity and raw worktree events reach the installed Bridge refresh gate")
        func canonicalWorkspaceActivityAndRawWorktreeEventsReachInstalledControllerGate() async throws {
            // Arrange
            let setup = try makeWorkspaceRefreshTestSetup()
            let harness = setup.harness
            let repoId = setup.repoId
            let worktree = setup.worktree
            let bridgePane = setup.bridgePane
            let controller = setup.controller

            // Assert — the native workspace mint propagates into the controller work gate.
            await expectBridgePaneActivity(
                .foreground,
                for: bridgePane.id,
                in: harness.coordinator,
                because: "the workspace pane is installed in the active native surface"
            )
            await expectControllerRefreshActivity(
                .foreground,
                controller: controller,
                because: "the canonical workspace activity was propagated to its installed controller"
            )

            // Act — hide through a canonical native fact, then send raw worktree events.
            harness.appLifecycleStore.setActive(false)
            await expectBridgePaneActivity(
                .loadedHidden,
                for: bridgePane.id,
                in: harness.coordinator,
                because: "the application became inactive"
            )
            await expectControllerRefreshActivity(
                .loadedHidden,
                controller: controller,
                because: "the controller must share the workspace activity authority"
            )
            let fileChangeset = FileChangeset(
                worktreeId: worktree.id,
                repoId: repoId,
                rootPath: worktree.path,
                paths: ["Sources/App/WorkspaceRefresh.swift"],
                timestamp: .now,
                batchSeq: 71
            )
            let latestStatus = GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(
                    changed: 3,
                    staged: 1,
                    untracked: 2
                ),
                branch: "feature/workspace-refresh",
                origin: nil
            )
            _ = await harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                RuntimeEnvelopeHarness.filesystemEnvelope(
                    event: .filesChanged(changeset: fileChangeset),
                    repoId: repoId,
                    worktreeId: worktree.id
                )
            )
            _ = await harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                RuntimeEnvelopeHarness.gitEnvelope(
                    event: .snapshotChanged(
                        snapshot: GitWorkingTreeSnapshot(
                            worktreeId: worktree.id,
                            repoId: repoId,
                            rootPath: worktree.path,
                            summary: latestStatus.summary,
                            branch: latestStatus.branch
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktree.id
                )
            )

            // Assert — both raw events used the one controller ingress and retained one dirty fact.
            let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            let dirtyFact = try #require(snapshot.dirtyFact)
            #expect(snapshot.activity == .loadedHidden)
            #expect(snapshot.activeRefreshPass == nil)
            #expect(snapshot.refreshPassCount == 0)
            #expect(dirtyFact.filePaths == ["Sources/App/WorkspaceRefresh.swift"])
            #expect(dirtyFact.latestFileStatus == latestStatus)
            #expect(dirtyFact.requiresReviewRefresh)

            await harness.finish()
        }

        @Test("stale pane projection retains Bridge product invalidation")
        func stalePaneProjectionRetainsBridgeProductInvalidation() async throws {
            // Arrange
            let projectionIndex = RefreshGateableFilesystemProjectionIndex()
            let setup = try makeWorkspaceRefreshTestSetup(projectionIndex: projectionIndex)
            let harness = setup.harness
            let controller = setup.controller
            harness.appLifecycleStore.setActive(false)
            await expectControllerRefreshActivity(
                .loadedHidden,
                controller: controller,
                because: "raw invalidation must remain pending while the pane is hidden"
            )
            let baselineSnapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            let baselineDirtyFact = try #require(baselineSnapshot.dirtyFact)
            let changeset = FileChangeset(
                worktreeId: setup.worktree.id,
                repoId: setup.repoId,
                rootPath: setup.worktree.path,
                paths: ["Sources/App/StaleProjection.swift"],
                containsGitInternalChanges: false,
                suppressedIgnoredPathCount: 1,
                suppressedGitInternalPathCount: 0,
                timestamp: .now,
                batchSeq: 81
            )
            let envelope = RuntimeEnvelopeHarness.filesystemEnvelope(
                event: .filesChanged(changeset: changeset),
                repoId: setup.repoId,
                worktreeId: setup.worktree.id
            )
            await projectionIndex.pauseNextProjection()

            // Act — suspend the index projection, advance its pane generation, then let the
            // stale projection finish.
            let projectionTask = Task { @MainActor in
                await harness.coordinator.handleFilesystemEnvelopeIfNeeded(envelope)
            }
            await projectionIndex.waitForPausedProjection()
            let pausedSnapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            #expect(pausedSnapshot.dirtyFact?.fileChangeset == nil)
            #expect(pausedSnapshot.dirtyFact?.generation == baselineDirtyFact.generation)
            harness.coordinator.upsertPaneFilesystemProjectionContext(for: setup.bridgePane)
            await projectionIndex.resumePausedProjection()
            #expect(await projectionTask.value)

            // Assert — pane projection staleness cannot discard the independent product invalidation fact.
            let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            let dirtyFact = try #require(snapshot.dirtyFact)
            let retainedChangeset = try #require(dirtyFact.fileChangeset)
            #expect(dirtyFact.generation == baselineDirtyFact.generation)
            #expect(retainedChangeset.paths == ["Sources/App/StaleProjection.swift"])
            #expect(retainedChangeset.batchSeq == 81)
            #expect(retainedChangeset.suppressedIgnoredPathCount == 1)
            #expect(dirtyFact.latestFileStatus == nil)
            #expect(dirtyFact.latestBatchSequence == changeset.batchSeq)
            #expect(dirtyFact.requiresReviewRefresh)
            #expect(snapshot.refreshPassCount == baselineSnapshot.refreshPassCount)

            await harness.finish()
        }

        @Test("filesystem changes outside the pane CWD do not invalidate Bridge product state")
        func filesystemChangesOutsidePaneCWDDoNotInvalidateBridgeProductState() async throws {
            // Arrange
            let setup = try makeWorkspaceRefreshTestSetup(bridgeCwdRelativePath: "Sources/FeatureA")
            let harness = setup.harness
            let controller = setup.controller
            harness.appLifecycleStore.setActive(false)
            await expectControllerRefreshActivity(
                .loadedHidden,
                controller: controller,
                because: "an unrelated filesystem event must leave the hidden pane idle"
            )
            let baselineSnapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            let baselineDirtyFact = try #require(baselineSnapshot.dirtyFact)

            // Act
            let unrelatedChangeset = FileChangeset(
                worktreeId: setup.worktree.id,
                repoId: setup.repoId,
                rootPath: setup.worktree.path,
                paths: ["Sources/FeatureB/Unrelated.swift"],
                timestamp: .now,
                batchSeq: 91
            )
            #expect(
                await harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                    RuntimeEnvelopeHarness.filesystemEnvelope(
                        event: .filesChanged(changeset: unrelatedChangeset),
                        repoId: setup.repoId,
                        worktreeId: setup.worktree.id
                    )
                )
            )

            // Assert
            let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            let dirtyFact = try #require(snapshot.dirtyFact)
            #expect(dirtyFact.generation == baselineDirtyFact.generation)
            #expect(dirtyFact.fileChangeset == nil)
            #expect(dirtyFact.latestFileStatus == nil)
            #expect(dirtyFact.latestBatchSequence == baselineDirtyFact.latestBatchSequence)
            #expect(dirtyFact.requiresReviewRefresh == baselineDirtyFact.requiresReviewRefresh)
            #expect(snapshot.refreshPassCount == baselineSnapshot.refreshPassCount)

            await harness.finish()
        }
    }
}

private struct WorkspaceRefreshTestSetup {
    let harness: BridgePaneActivityTestHarness
    let repoId: UUID
    let worktree: Worktree
    let bridgePane: Pane
    let controller: BridgePaneController
}

@MainActor
private func makeWorkspaceRefreshTestSetup(
    projectionIndex: (any WorkspaceFilesystemProjectionIndexing)? = nil,
    bridgeCwdRelativePath: String? = nil
) throws -> WorkspaceRefreshTestSetup {
    let harness = makeBridgePaneActivityTestHarness(
        filesystemProjectionIndex: projectionIndex
    )
    let repo = harness.store.addRepo(
        at: harness.tempDirectory.appending(path: "refresh-admission-repo")
    )
    let worktree = try #require(
        harness.store.repo(repo.id)?.worktrees.first(where: { $0.isMainWorktree })
    )
    let bridgeCwd = bridgeCwdRelativePath.map { worktree.path.appending(path: $0) } ?? worktree.path
    let paneState = BridgePaneState(
        panelKind: .diffViewer,
        source: .workspace(rootPath: worktree.path.path, baseline: .headMinusOne)
    )
    let bridgePane = harness.store.createPane(
        content: .bridgePanel(paneState),
        metadata: PaneMetadata(
            contentType: .diff,
            title: "Workspace refresh",
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: bridgeCwd
            )
        )
    )
    let workspaceTab = Tab(paneId: bridgePane.id, name: "Workspace refresh")
    harness.store.appendTab(workspaceTab)
    harness.store.setActiveTab(workspaceTab.id)
    harness.viewRegistry.ensureSlot(for: bridgePane.id)
    let controller = BridgePaneController(
        paneId: bridgePane.id,
        state: paneState,
        appRootURL: testBridgeAppRootURL(),
        metadata: bridgePane.metadata,
        initialPaneActivity: .dormant
    )
    harness.coordinator.registerHostedView(
        mountedView: BridgePaneMountView(paneId: bridgePane.id, controller: controller),
        for: bridgePane.id
    )
    harness.coordinator.upsertPaneFilesystemProjectionContext(for: bridgePane)
    enterForegroundNativeEnvironment(harness)
    harness.coordinator.refreshBridgePaneActivities()
    return WorkspaceRefreshTestSetup(
        harness: harness,
        repoId: repo.id,
        worktree: worktree,
        bridgePane: bridgePane,
        controller: controller
    )
}

private actor RefreshGateableFilesystemProjectionIndex: WorkspaceFilesystemProjectionIndexing {
    private let base = FilesystemProjectionIndex()
    private var shouldPauseNextProjection = false
    private var pausedProjectionWaiters: [CheckedContinuation<Void, Never>] = []
    private var pausedProjectionRelease: CheckedContinuation<Void, Never>?
    private var projectionIsPaused = false

    func shutdown() async {
        await base.shutdown()
    }

    func pauseNextProjection() {
        shouldPauseNextProjection = true
    }

    func waitForPausedProjection() async {
        guard !projectionIsPaused else { return }
        await withCheckedContinuation { continuation in
            pausedProjectionWaiters.append(continuation)
        }
    }

    func resumePausedProjection() {
        pausedProjectionRelease?.resume()
        pausedProjectionRelease = nil
        projectionIsPaused = false
    }

    func reconcileSourceSync(_ request: FilesystemSourceSyncRequest) async -> FilesystemSourceSyncDiff {
        await base.reconcileSourceSync(request)
    }

    func commitSourceSync(requestGeneration: UInt64, topologyGeneration: UInt64) async -> Bool {
        await base.commitSourceSync(
            requestGeneration: requestGeneration,
            topologyGeneration: topologyGeneration
        )
    }

    func applyPaneUpdate(
        _ update: FilesystemProjectionPaneUpdate
    ) async -> FilesystemProjectionPaneUpdateOutcome {
        await base.applyPaneUpdate(update)
    }

    func projectPaneFilesystem(
        _ request: PaneFilesystemProjectionRequest
    ) async -> PaneFilesystemProjectionResult {
        if shouldPauseNextProjection {
            shouldPauseNextProjection = false
            projectionIsPaused = true
            let waiters = pausedProjectionWaiters
            pausedProjectionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                pausedProjectionRelease = continuation
            }
        }
        return await base.projectPaneFilesystem(request)
    }
}

@MainActor
private func expectControllerRefreshActivity(
    _ expectedActivity: BridgePaneActivity,
    controller: BridgePaneController,
    because description: String,
    maxTurns: Int = 200
) async {
    for _ in 0..<maxTurns {
        if controller.refreshAdmissionCoordinator.diagnosticSnapshot.activity == expectedActivity {
            return
        }
        await Task.yield()
    }
    #expect(
        controller.refreshAdmissionCoordinator.diagnosticSnapshot.activity == expectedActivity,
        "Expected controller refresh activity \(expectedActivity.rawValue) because \(description)"
    )
}
