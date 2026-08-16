import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorCWDIdentityTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("one CWD fact performs one coordinator topology lookup and pane mutation attempt")
    func oneCWDFactPerformsOneCoordinatorLookupAndMutationAttempt() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-single-cwd-authority-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: traceDirectory) }
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "single-cwd-authority",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 928,
            timeUnixNano: { 126 }
        )
        let performanceTraceRecorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        let bus = makeTestPaneRuntimeEventBus()
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/single-cwd-authority-repo"))
        let pane = store.createPane(
            launchDirectory: repo.repoPath,
            title: "Terminal",
            facets: PaneContextFacets(
                repoId: repo.id,
                worktreeId: repo.worktrees[0].id,
                cwd: repo.repoPath
            )
        )
        store.appendTab(Tab(paneId: pane.id))
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: CWDIdentitySurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: bus,
            windowLifecycleStore: WindowLifecycleAtom(),
            bridgePaneAttendance: BridgePaneAttendanceAtom(),
            performanceTraceRecorder: performanceTraceRecorder
        )
        let rawCwdPath = repo.repoPath.appending(path: "Sources").path
        let normalizedCwd = try #require(CWDNormalizer.normalize(rawCwdPath))

        _ = await bus.post(
            RuntimeEnvelopeHarness.paneEnvelope(
                event: .terminal(.cwdChanged(rawCwdPath)),
                paneId: PaneId(existingUUID: pane.id)
            )
        )
        await eventually("runtime CWD fact should finish coordinator handling") {
            store.pane(pane.id)?.metadata.cwd?.standardizedFileURL.path == normalizedCwd.standardizedFileURL.path
        }
        try await performanceTraceRecorder.drain()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let traceContents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let topologyLookupRecords = traceContents.split(separator: "\n").filter {
            $0.contains("\"body\":\"performance.topology.repo_and_worktree\"")
        }
        #expect(topologyLookupRecords.count == 1)

        await coordinator.shutdown()
    }

    @Test("runtime cwd event preserves normalized full cwd and refreshes live identity")
    func runtimeCwdEventPreservesNormalizedFullCwdAndRefreshesLiveIdentity() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-cwd-\(UUID().uuidString)")
        let bus = makeTestPaneRuntimeEventBus()
        let store = WorkspaceStore()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: CWDIdentitySurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: bus
        )

        let repo = store.addRepo(at: URL(filePath: "/tmp/runtime-cwd-repo"))
        let mainWorktree = Worktree(
            repoId: repo.id,
            name: "main",
            path: repo.repoPath,
            isMainWorktree: true
        )
        let featureWorktree = Worktree(
            repoId: repo.id,
            name: "feature",
            path: URL(filePath: "/tmp/runtime-cwd-repo-feature")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [mainWorktree, featureWorktree])
        let pane = store.createPane(
            launchDirectory: mainWorktree.path,
            title: "Terminal",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: mainWorktree.id, cwd: mainWorktree.path)
        )
        store.appendTab(Tab(paneId: pane.id))

        let rawCwdPath = "/tmp/runtime-cwd-repo-feature/../runtime-cwd-repo-feature/Sources"
        let normalizedCwd = try #require(CWDNormalizer.normalize(rawCwdPath))
        let expectedCwd = URL(filePath: normalizedCwd.path, directoryHint: .isDirectory)
        _ = await bus.post(
            RuntimeEnvelopeHarness.paneEnvelope(
                event: .terminal(.cwdChanged(rawCwdPath)),
                paneId: PaneId(existingUUID: pane.id)
            )
        )

        await eventually("runtime cwd event should refresh pane live identity") {
            store.pane(pane.id)?.metadata.cwd == expectedCwd
                && store.pane(pane.id)?.worktreeId == featureWorktree.id
        }

        let updated = store.pane(pane.id)
        #expect(updated?.metadata.launchDirectory == pane.metadata.launchDirectory)
        #expect(updated?.metadata.cwd == expectedCwd)
        #expect(updated?.repoId == repo.id)
        #expect(updated?.worktreeId == featureWorktree.id)
        #expect(updated?.metadata.worktreeName == "feature")
        #expect(PaneDisplayDerived().displayParts(for: updated!).worktreeFolderName == "feature")

        await coordinator.shutdown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("temporary repo unavailability retains association and preserved topology heals moved CWD")
    func temporaryRepoUnavailabilityRetainsAndHealsAssociation() async throws {
        let bus = makeTestPaneRuntimeEventBus()
        let store = WorkspaceStore()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: CWDIdentitySurfaceManager(),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: bus
        )

        let repository = store.addRepo(at: URL(filePath: "/tmp/runtime-cwd-unavailable-repo"))
        let firstWorktree = try #require(repository.worktrees.first)
        let secondWorktree = Worktree(
            repoId: repository.id,
            name: "feature",
            path: URL(filePath: "/tmp/runtime-cwd-unavailable-feature")
        )
        store.reconcileDiscoveredWorktrees(
            repository.id,
            worktrees: [firstWorktree, secondWorktree]
        )
        let pane = store.createPane(
            launchDirectory: firstWorktree.path,
            facets: PaneContextFacets(
                repoId: repository.id,
                worktreeId: firstWorktree.id,
                cwd: firstWorktree.path
            )
        )
        store.appendTab(Tab(paneId: pane.id))
        store.markRepoUnavailable(repository.id)

        _ = await bus.post(
            RuntimeEnvelopeHarness.paneEnvelope(
                event: .terminal(.cwdChanged(secondWorktree.path.path)),
                paneId: PaneId(existingUUID: pane.id)
            )
        )
        await eventually("uncertain CWD update should retain the known association") {
            let facets = store.paneAtom.graphAtom.paneState(pane.id)?.durableContextFacets
            return facets?.cwd?.standardizedFileURL.path
                == secondWorktree.path.standardizedFileURL.path
                && facets?.repoId == repository.id
                && facets?.worktreeId == firstWorktree.id
        }
        let unavailableFacets = store.paneAtom.graphAtom.paneState(pane.id)?.durableContextFacets
        #expect(
            unavailableFacets?.cwd?.standardizedFileURL.path
                == secondWorktree.path.standardizedFileURL.path
        )
        #expect(unavailableFacets?.repoId == repository.id)
        #expect(unavailableFacets?.worktreeId == firstWorktree.id)

        let reconciliation = store.mutationCoordinator.reconcileDiscoveredWorktrees(
            repository.id,
            worktrees: [firstWorktree, secondWorktree]
        )
        guard case .accepted(let acceptedReconciliation) = reconciliation else {
            Issue.record("preserved topology should be accepted after temporary unavailability")
            await coordinator.shutdown()
            return
        }
        coordinator.topologyDidChange(acceptedReconciliation.delta)

        let healedFacets = store.paneAtom.graphAtom.paneState(pane.id)?.durableContextFacets
        #expect(!store.isRepoUnavailable(repository.id))
        #expect(healedFacets?.repoId == repository.id)
        #expect(healedFacets?.worktreeId == secondWorktree.id)
        #expect(store.pane(pane.id)?.residency == .active)
        await coordinator.shutdown()
    }

}

@MainActor
private final class CWDIdentitySurfaceManager: WorkspaceSurfaceManaging {
    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}
