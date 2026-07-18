import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceBridgeConstructionIntegrationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("actual Bridge view factory gives two panes File authority from one application coordinator")
    func bridgeViewFactoryInjectsOneApplicationCoordinator() async throws {
        // Arrange
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator()
        let harness = makeBridgePaneActivityTestHarness(
            worktreeProductConstructionCoordinator: constructionCoordinator
        )
        let setup = try makeTwoPaneWorktreeSetup(in: harness)
        enterForegroundNativeEnvironment(harness)

        // Act
        let firstView = harness.coordinator.createBridgePaneView(
            for: setup.firstPane,
            state: setup.state
        )
        let secondView = harness.coordinator.createBridgePaneView(
            for: setup.secondPane,
            state: setup.state
        )

        // Assert
        #expect(
            harness.coordinator.worktreeProductConstructionCoordinator
                === constructionCoordinator
        )
        try await expectAvailableFileSource(
            from: firstView.controller,
            repoId: setup.repoId,
            worktreeId: setup.worktree.id
        )
        try await expectAvailableFileSource(
            from: secondView.controller,
            repoId: setup.repoId,
            worktreeId: setup.worktree.id
        )

        await harness.finish()
    }

    @Test("one worktree freshness advance precedes invalidation fan-out to both panes")
    func freshnessAdvancesOnceBeforePaneFanOut() async throws {
        // Arrange
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator(
            eventSink: eventProbe.eventSink
        )
        let harness = makeBridgePaneActivityTestHarness(
            worktreeProductConstructionCoordinator: constructionCoordinator
        )
        let setup = try makeTwoPaneWorktreeSetup(in: harness)
        enterForegroundNativeEnvironment(harness)
        let firstView = harness.coordinator.createBridgePaneView(
            for: setup.firstPane,
            state: setup.state
        )
        let secondView = harness.coordinator.createBridgePaneView(
            for: setup.secondPane,
            state: setup.state
        )
        let owner = BridgeWorktreeProductOwnerKey(
            repoIdentity: setup.repoId.uuidString,
            worktreeIdentity: setup.worktree.id.uuidString,
            stableRootIdentity: StableKey.fromPath(setup.worktree.path),
            providerIdentity: "integration-provider"
        )
        let key = makeBridgeReviewConstructionKey(owner: owner)
        let gate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeReviewConstructionArtifact()
        )
        let oldAcquisition = Task {
            try await constructionCoordinator.acquire(key: key, build: gate.run)
        }
        await gate.waitUntilStarted()
        let changeset = FileChangeset(
            worktreeId: setup.worktree.id,
            repoId: setup.repoId,
            rootPath: setup.worktree.path,
            paths: ["Sources/Changed.swift"],
            timestamp: .now,
            batchSeq: 1
        )

        // Act
        _ = await harness.coordinator.handleFilesystemEnvelopeIfNeeded(
            RuntimeEnvelopeHarness.filesystemEnvelope(
                event: .filesChanged(changeset: changeset),
                repoId: setup.repoId,
                worktreeId: setup.worktree.id
            )
        )
        let oldResult = await oldAcquisition.result
        await gate.release(invocation: 1)
        _ = await eventProbe.waitFor(.staleCompletionDropped)
        let currentAcquisition = Task {
            try await constructionCoordinator.acquire(key: key, build: gate.run)
        }
        await gate.waitUntilStarted(count: 2)
        await gate.release(invocation: 2)
        let currentLease = try await currentAcquisition.value

        // Assert
        guard case .failure(let oldError) = oldResult else {
            Issue.record("The stale pre-envelope construction unexpectedly published")
            return
        }
        #expect(oldError as? BridgeWorktreeProductConstructionError == .invalidated)
        #expect(currentLease.epoch.rawValue == 2)
        #expect(await gate.recordedInvocationCount() == 2)
        let hiddenPaneRefresh =
            firstView.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        let foregroundPaneRefresh =
            secondView.controller.refreshAdmissionCoordinator.diagnosticSnapshot
        #expect(hiddenPaneRefresh.dirtyFact?.filePaths == ["Sources/Changed.swift"])
        #expect(hiddenPaneRefresh.refreshPassCount == 0)
        #expect(foregroundPaneRefresh.dirtyFact == nil)
        #expect(foregroundPaneRefresh.refreshPassCount == 1)

        await constructionCoordinator.release(currentLease)
        await harness.finish()
    }

    @Test("workspace shutdown closes and physically drains shared construction")
    func workspaceShutdownClosesAndDrainsConstruction() async throws {
        // Arrange
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator()
        let harness = makeBridgePaneActivityTestHarness(
            worktreeProductConstructionCoordinator: constructionCoordinator
        )
        let gate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeReviewConstructionArtifact()
        )
        let acquisition = Task {
            try await constructionCoordinator.acquire(
                key: makeBridgeReviewConstructionKey(),
                build: gate.run
            )
        }
        await gate.waitUntilStarted()

        // Act
        let workspaceShutdown = Task { @MainActor in
            await harness.coordinator.shutdown()
        }
        let acquisitionResult = await acquisition.result

        // Assert
        guard case .failure(let error) = acquisitionResult else {
            Issue.record("Workspace shutdown unexpectedly published shared construction")
            return
        }
        #expect(error as? BridgeWorktreeProductConstructionError == .coordinatorClosed)
        let drainingSnapshot = await constructionCoordinator.snapshot()
        #expect(drainingSnapshot.inFlightCount == 1)
        #expect(drainingSnapshot.drainingTombstoneCount == 1)

        await gate.release()
        await workspaceShutdown.value
        await assertBridgeConstructionCoordinatorDrained(constructionCoordinator)
        try? FileManager.default.removeItem(at: harness.tempDirectory)
    }

    @Test("matching Git snapshot advances the canonical worktree freshness")
    func matchingGitSnapshotAdvancesFreshness() async throws {
        // Arrange
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator(
            eventSink: eventProbe.eventSink
        )
        let harness = makeBridgePaneActivityTestHarness(
            worktreeProductConstructionCoordinator: constructionCoordinator
        )
        let setup = try makeTwoPaneWorktreeSetup(in: harness)
        let owner = BridgeWorktreeProductOwnerKey(
            repoIdentity: setup.repoId.uuidString,
            worktreeIdentity: setup.worktree.id.uuidString,
            stableRootIdentity: StableKey.fromPath(setup.worktree.path),
            providerIdentity: "snapshot-integration-provider"
        )
        let key = makeBridgeReviewConstructionKey(owner: owner)
        let gate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeReviewConstructionArtifact()
        )
        let oldAcquisition = Task {
            try await constructionCoordinator.acquire(key: key, build: gate.run)
        }
        await gate.waitUntilStarted()

        // Act
        _ = await harness.coordinator.handleFilesystemEnvelopeIfNeeded(
            RuntimeEnvelopeHarness.gitEnvelope(
                event: .snapshotChanged(
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: setup.worktree.id,
                        repoId: setup.repoId,
                        rootPath: setup.worktree.path,
                        summary: .init(changed: 1, staged: 0, untracked: 0),
                        branch: "feature/shared-construction"
                    )
                ),
                repoId: setup.repoId,
                worktreeId: setup.worktree.id
            )
        )
        let oldResult = await oldAcquisition.result
        await gate.release(invocation: 1)
        _ = await eventProbe.waitFor(.staleCompletionDropped)
        let currentAcquisition = Task {
            try await constructionCoordinator.acquire(key: key, build: gate.run)
        }
        await gate.waitUntilStarted(count: 2)
        await gate.release(invocation: 2)
        let currentLease = try await currentAcquisition.value

        // Assert
        guard case .failure(let oldError) = oldResult else {
            Issue.record("The pre-snapshot construction unexpectedly published")
            return
        }
        #expect(oldError as? BridgeWorktreeProductConstructionError == .invalidated)
        #expect(currentLease.epoch.rawValue == 2)

        await constructionCoordinator.release(currentLease)
        await harness.finish()
    }

    @Test("unresolved topology does not invent a worktree construction identity")
    func unresolvedTopologyDoesNotAdvanceFreshness() async throws {
        // Arrange
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator()
        let harness = makeBridgePaneActivityTestHarness(
            worktreeProductConstructionCoordinator: constructionCoordinator
        )
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = harness.tempDirectory.appending(path: "unresolved-worktree")
        let owner = BridgeWorktreeProductOwnerKey(
            repoIdentity: repoId.uuidString,
            worktreeIdentity: worktreeId.uuidString,
            stableRootIdentity: StableKey.fromPath(rootPath),
            providerIdentity: "unresolved-integration-provider"
        )
        let key = makeBridgeReviewConstructionKey(owner: owner)
        let gate = BridgeWorktreeProductConstructionGate(
            artifact: makeBridgeReviewConstructionArtifact()
        )
        let acquisition = Task {
            try await constructionCoordinator.acquire(key: key, build: gate.run)
        }
        await gate.waitUntilStarted()

        // Act
        _ = await harness.coordinator.handleFilesystemEnvelopeIfNeeded(
            RuntimeEnvelopeHarness.filesystemEnvelope(
                event: .filesChanged(
                    changeset: FileChangeset(
                        worktreeId: worktreeId,
                        repoId: repoId,
                        rootPath: rootPath,
                        paths: ["Sources/Unresolved.swift"],
                        timestamp: .now,
                        batchSeq: 1
                    )
                ),
                repoId: repoId,
                worktreeId: worktreeId
            )
        )
        await gate.release()
        let lease = try await acquisition.value

        // Assert
        #expect(lease.epoch.rawValue == 1)
        #expect(await gate.recordedInvocationCount() == 1)

        await constructionCoordinator.release(lease)
        await harness.finish()
    }
}

private struct TwoPaneWorktreeSetup {
    let repoId: UUID
    let worktree: Worktree
    let state: BridgePaneState
    let firstPane: Pane
    let secondPane: Pane
}

@MainActor
private func makeTwoPaneWorktreeSetup(
    in harness: BridgePaneActivityTestHarness
) throws -> TwoPaneWorktreeSetup {
    let repo = harness.store.addRepo(
        at: harness.tempDirectory.appending(path: "shared-construction-repo")
    )
    let worktree = try #require(
        harness.store.repo(repo.id)?.worktrees.first(where: { $0.isMainWorktree })
    )
    let state = BridgePaneState(
        panelKind: .diffViewer,
        source: .workspace(rootPath: worktree.path.path, baseline: .headMinusOne)
    )
    let firstPane = makeBridgePane(
        title: "First shared construction pane",
        repo: repo,
        worktree: worktree,
        state: state,
        store: harness.store
    )
    let secondPane = makeBridgePane(
        title: "Second shared construction pane",
        repo: repo,
        worktree: worktree,
        state: state,
        store: harness.store
    )
    harness.viewRegistry.ensureSlot(for: firstPane.id)
    harness.viewRegistry.ensureSlot(for: secondPane.id)
    harness.store.appendTab(Tab(paneId: firstPane.id, name: "First shared construction pane"))
    let secondTab = Tab(paneId: secondPane.id, name: "Second shared construction pane")
    harness.store.appendTab(secondTab)
    harness.store.setActiveTab(secondTab.id)
    return TwoPaneWorktreeSetup(
        repoId: repo.id,
        worktree: worktree,
        state: state,
        firstPane: firstPane,
        secondPane: secondPane
    )
}

@MainActor
private func makeBridgePane(
    title: String,
    repo: Repo,
    worktree: Worktree,
    state: BridgePaneState,
    store: WorkspaceStore
) -> Pane {
    store.createPane(
        content: .bridgePanel(state),
        metadata: PaneMetadata(
            contentType: .diff,
            title: title,
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: worktree.path
            )
        )
    )
}

@MainActor
private func expectAvailableFileSource(
    from controller: BridgePaneController,
    repoId: UUID,
    worktreeId: UUID
) async throws {
    let provider = try #require(controller.productSchemeProvider)
    let request = try bridgeFileSourceCurrentRequest(paneId: controller.paneId)
    guard case .callCompleted(let response) = await provider.response(for: request),
        case .fileSourceCurrent(.available(let source)) = response.call
    else {
        Issue.record("Expected production-injected File source authority")
        return
    }
    #expect(source.repoId == repoId.uuidString)
    #expect(source.worktreeId == worktreeId.uuidString)
}

private func bridgeFileSourceCurrentRequest(paneId: UUID) throws -> BridgeProductControlRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductControlRequest.self,
        from: JSONSerialization.data(
            withJSONObject: [
                "call": [
                    "method": "file.source.current",
                    "request": [:],
                ],
                "kind": "product.call",
                "paneSessionId": paneId.uuidString,
                "requestId": "shared-construction-source-current",
                "requestSequence": 1,
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": 1,
                "workerInstanceId": "shared-construction-worker",
            ],
            options: [.sortedKeys]
        )
    )
}
