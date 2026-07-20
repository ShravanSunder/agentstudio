import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct WorkspaceBridgePaneRefreshIntegrationTests {
        init() {
            installTestAtomRegistryIfNeeded()
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

        @Test("raw worktree invalidation is recorded once when derived projection becomes stale")
        func rawWorktreeInvalidationIsRecordedOnceWhenDerivedProjectionBecomesStale() async throws {
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

            // Act — suspend the derived projection, advance its pane generation, then let the
            // stale projection finish. The exact raw repo/worktree event remains authoritative.
            let projectionTask = Task { @MainActor in
                await harness.coordinator.handleFilesystemEnvelopeIfNeeded(envelope)
            }
            await projectionIndex.waitForPausedProjection()
            harness.coordinator.upsertPaneFilesystemProjectionContext(for: setup.bridgePane)
            await projectionIndex.resumePausedProjection()
            #expect(await projectionTask.value)

            // Assert — one raw record survives even though the derived projection is discarded.
            // The additive suppressed count detects accidental double routing.
            let snapshot = controller.refreshAdmissionCoordinator.diagnosticSnapshot
            let dirtyFact = snapshot.dirtyFact
            #expect(dirtyFact?.filePaths == ["Sources/App/StaleProjection.swift"])
            #expect(dirtyFact?.latestBatchSequence == 81)
            #expect(dirtyFact?.fileChangeset?.suppressedIgnoredPathCount == 1)
            #expect(snapshot.refreshPassCount == 0)

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
    projectionIndex: (any WorkspaceFilesystemProjectionIndexing)? = nil
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
                cwd: worktree.path
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
