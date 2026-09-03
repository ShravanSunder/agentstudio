import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
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

            // Act — move the pane into background residency, then send raw worktree events.
            harness.store.paneAtom.setResidency(.backgrounded, for: bridgePane.id)
            await expectBridgePaneActivity(
                .loadedHidden,
                for: bridgePane.id,
                in: harness.coordinator,
                because: "the pane moved to background residency"
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
            harness.store.paneAtom.setResidency(.backgrounded, for: setup.bridgePane.id)
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
            harness.store.paneAtom.setResidency(.backgrounded, for: setup.bridgePane.id)
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

        @Test("same-repo Git-internal invalidation refreshes contribution review without replacement state")
        func sameRepoGitInternalInvalidationCrossesWorktreesForContributionReview() async throws {
            // Arrange
            let setup = try makeWorkspaceRefreshTestSetup(addCrossWorktreeEventSource: true)
            await prepareHiddenBridgePaneForCrossWorktreeInvalidation(setup)
            let generationBeforeInvalidation = setup.controller.nextReviewGeneration

            // Act
            _ = await setup.harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                crossWorktreeFilesystemEnvelope(
                    setup: setup,
                    containsGitInternalChanges: true,
                    batchSeq: 91
                )
            )

            // Assert
            #expect(setup.controller.nextReviewGeneration == generationBeforeInvalidation)
            #expect(setup.controller.pendingComparisonReviewGeneration == nil)
            #expect(
                setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact?
                    .requiresReviewRefresh == true
            )

            await setup.harness.finish()
        }

        @Test("cross-worktree Git-internal invalidation records Review-only dirty state")
        func crossWorktreeGitInternalInvalidationRecordsReviewOnlyDirtyState() async throws {
            // Arrange
            let setup = try makeWorkspaceRefreshTestSetup(addCrossWorktreeEventSource: true)
            await prepareHiddenBridgePaneForCrossWorktreeInvalidation(setup)

            // Act
            _ = await setup.harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                crossWorktreeFilesystemEnvelope(
                    setup: setup,
                    containsGitInternalChanges: true,
                    batchSeq: 92
                )
            )

            // Assert
            let dirtyFact = try #require(
                setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact
            )
            #expect(dirtyFact.fileChangeset == nil)
            #expect(dirtyFact.filePaths.isEmpty)
            #expect(dirtyFact.latestBatchSequence == 0)
            #expect(dirtyFact.requiresReviewRefresh)

            await setup.harness.finish()
        }

        @Test("suppressed-only Git-internal duplicates do not enter comparison replacement state")
        func suppressedOnlyGitInternalDuplicatesDoNotEnterComparisonReplacementState() async throws {
            // Arrange
            let setup = try makeWorkspaceRefreshTestSetup(addCrossWorktreeEventSource: true)
            await prepareHiddenBridgePaneForCrossWorktreeInvalidation(setup)
            let generationBeforeInvalidation = setup.controller.nextReviewGeneration

            // Act
            let suppressedOnlyEnvelope = crossWorktreeFilesystemEnvelope(
                setup: setup,
                suppressedGitInternalPathCount: 1,
                batchSeq: 93
            )
            _ = await setup.harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                suppressedOnlyEnvelope
            )
            _ = await setup.harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                suppressedOnlyEnvelope
            )

            // Assert
            #expect(setup.controller.pendingComparisonReviewGeneration == nil)
            #expect(setup.controller.nextReviewGeneration == generationBeforeInvalidation)
            #expect(
                setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact?
                    .fileChangeset == nil
            )

            await setup.harness.finish()
        }

        @Test("ordinary file invalidation does not cross worktrees")
        func ordinaryFileInvalidationDoesNotCrossWorktrees() async throws {
            // Arrange
            let setup = try makeWorkspaceRefreshTestSetup(addCrossWorktreeEventSource: true)
            await prepareHiddenBridgePaneForCrossWorktreeInvalidation(setup)
            let generationBeforeInvalidation = setup.controller.nextReviewGeneration

            // Act
            _ = await setup.harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                crossWorktreeFilesystemEnvelope(
                    setup: setup,
                    paths: ["Sources/App/OtherWorktree.swift"],
                    batchSeq: 94
                )
            )

            // Assert
            #expect(
                setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact == nil
            )
            #expect(setup.controller.nextReviewGeneration == generationBeforeInvalidation)
            #expect(setup.controller.pendingComparisonReviewGeneration == nil)

            await setup.harness.finish()
        }

        @Test(
            "staged and unstaged panes ignore cross-worktree Git-internal invalidation",
            arguments: [WorkspaceBaseline.staged, .unstaged]
        )
        func nonContributionPanesIgnoreCrossWorktreeGitInternalInvalidation(
            baseline: WorkspaceBaseline
        ) async throws {
            // Arrange
            let setup = try makeWorkspaceRefreshTestSetup(
                baseline: baseline,
                addCrossWorktreeEventSource: true
            )
            await prepareHiddenBridgePaneForCrossWorktreeInvalidation(setup)
            let generationBeforeInvalidation = setup.controller.nextReviewGeneration

            // Act
            _ = await setup.harness.coordinator.handleFilesystemEnvelopeIfNeeded(
                crossWorktreeFilesystemEnvelope(
                    setup: setup,
                    containsGitInternalChanges: true,
                    batchSeq: 95
                )
            )

            // Assert
            #expect(
                setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact == nil
            )
            #expect(setup.controller.nextReviewGeneration == generationBeforeInvalidation)
            #expect(setup.controller.pendingComparisonReviewGeneration == nil)

            await setup.harness.finish()
        }
    }
}

private struct WorkspaceRefreshTestSetup {
    let harness: BridgePaneActivityTestHarness
    let repoId: UUID
    let worktree: Worktree
    let eventWorktree: Worktree
    let bridgePane: Pane
    let controller: BridgePaneController
}

@MainActor
private func makeWorkspaceRefreshTestSetup(
    projectionIndex: (any WorkspaceFilesystemProjectionIndexing)? = nil,
    bridgeCwdRelativePath: String? = nil,
    baseline: WorkspaceBaseline = .ref(name: "HEAD~1"),
    addCrossWorktreeEventSource: Bool = false
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
    let eventWorktree: Worktree
    if addCrossWorktreeEventSource {
        eventWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repo.id,
            name: "cross-worktree-event-source",
            path: harness.tempDirectory.appending(path: "cross-worktree-event-source")
        )
        harness.store.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [worktree, eventWorktree]
        )
    } else {
        eventWorktree = worktree
    }
    let paneState = BridgePaneState(
        panelKind: .diffViewer,
        source: .workspace(
            rootPath: worktree.path.path,
            baseline: baseline)
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
        eventWorktree: eventWorktree,
        bridgePane: bridgePane,
        controller: controller
    )
}

@MainActor
private func prepareHiddenBridgePaneForCrossWorktreeInvalidation(
    _ setup: WorkspaceRefreshTestSetup
) async {
    #expect(setup.eventWorktree.id != setup.worktree.id)
    #expect(setup.eventWorktree.repoId == setup.repoId)
    #expect(setup.worktree.repoId == setup.repoId)
    await waitForActiveReviewRefreshTaskToFinish(setup.controller)
    setup.harness.store.paneAtom.setResidency(.backgrounded, for: setup.bridgePane.id)
    await expectControllerRefreshActivity(
        .loadedHidden,
        controller: setup.controller,
        because: "cross-worktree invalidation must remain inspectable as pending work"
    )
}

private func crossWorktreeFilesystemEnvelope(
    setup: WorkspaceRefreshTestSetup,
    paths: [String] = [],
    containsGitInternalChanges: Bool = false,
    suppressedGitInternalPathCount: Int = 0,
    batchSeq: UInt64
) -> RuntimeEnvelope {
    let changeset = FileChangeset(
        worktreeId: setup.eventWorktree.id,
        repoId: setup.repoId,
        rootPath: setup.eventWorktree.path,
        paths: paths,
        containsGitInternalChanges: containsGitInternalChanges,
        suppressedGitInternalPathCount: suppressedGitInternalPathCount,
        timestamp: .now,
        batchSeq: batchSeq
    )
    return RuntimeEnvelopeHarness.filesystemEnvelope(
        event: .filesChanged(changeset: changeset),
        repoId: setup.repoId,
        worktreeId: setup.eventWorktree.id
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
