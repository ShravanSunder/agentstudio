import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Darwin
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

private final class RepoExplorerProjectionExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedExecutionCount = 0
    private var storedFullExecutionCount = 0
    private var storedDeltaExecutionCount = 0

    var executionCount: Int {
        lock.withLock { storedExecutionCount }
    }

    var fullExecutionCount: Int {
        lock.withLock { storedFullExecutionCount }
    }

    var deltaExecutionCount: Int {
        lock.withLock { storedDeltaExecutionCount }
    }

    func recordExecution(_ work: RepoExplorerProjectionWork) {
        lock.withLock {
            storedExecutionCount += 1
            switch work {
            case .full:
                storedFullExecutionCount += 1
            case .delta:
                storedDeltaExecutionCount += 1
            }
        }
    }
}

@MainActor
private func makeProjectionPreferences(atoms: CoreAtoms) -> RepoExplorerSidebarPrefsAtom {
    RepoExplorerSidebarPrefsAtom(sidebarState: atoms.workspaceSidebarState)
}

@Suite("RepoExplorer projection demand")
struct RepoExplorerProjectionDemandTests {
    @MainActor
    @Test("demand waits for synchronous rowless R0 host registration before first admission")
    func demandWaitsForRowlessR0BeforeFirstAdmission() async {
        await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: RepoExplorerSidebarPrefsAtom(),
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { _ in nil }
            )
            let recorder = RepoExplorerProjectionExecutionRecorder()
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                project: { work throws(CancellationError) in
                    recorder.recordExecution(work)
                    do {
                        return try RepoExplorerProjectionWorker.project(work)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        preconditionFailure("Unexpected projection failure: \(error)")
                    }
                }
            )
            defer { adapter.stop() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<20 { await Task.yield() }

            #expect(adapter.cachedProjectionRequest == nil)
            #expect(recorder.executionCount == 0)

            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }
            for _ in 0..<400 where adapter.publishedResult == nil {
                await Task.yield()
            }

            #expect(recorder.executionCount == 1)
            #expect(host.acceptedBaseline?.revision == 0)
            #expect(host.acceptedBaseline?.visibleGeneration == 0)
            #expect(adapter.acknowledgedMaterializationBaseline == host.acceptedBaseline)
        }
    }

    @MainActor
    @Test("By Repository pane activity performs zero capture execution and publication")
    func byRepositoryRejectsPaneActivityBeforeCapture() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-adapter-admission"))
            let worktree = try #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "before",
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            atoms.repoCache.setRepoEnrichment(
                .resolvedLocal(
                    repoId: repo.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: repo.name),
                    updatedAt: Date()
                )
            )
            let preferences = makeProjectionPreferences(atoms: atoms)
            preferences.setGroupingMode(.repo, for: .repos)
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: preferences,
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { paneID in
                    atoms.paneActivityStatus.status(for: paneID)
                }
            )
            let recorder = RepoExplorerProjectionExecutionRecorder()
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                project: { work throws(CancellationError) in
                    recorder.recordExecution(work)
                    do {
                        return try RepoExplorerProjectionWorker.project(work)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        preconditionFailure("Unexpected projection failure: \(error)")
                    }
                }
            )
            defer { adapter.stop() }
            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.publishedResult == nil {
                await Task.yield()
            }
            let baselineExecutionCount = recorder.executionCount
            let baselineRevision = adapter.publishedRevision
            #expect(baselineExecutionCount == 1)
            #expect(adapter.observationRegistration.paneIDs.isEmpty)

            store.paneAtom.updatePaneTitle(pane.id, title: "after")
            atoms.paneActivityStatus.recordSettledActivity(
                paneId: pane.id,
                lastOutputLine: "activity changed"
            )
            for _ in 0..<200 { await Task.yield() }

            #expect(recorder.executionCount == baselineExecutionCount)
            #expect(adapter.publishedRevision == baselineRevision)
        }
    }

    @MainActor
    @Test("Repos activity subgroup carries the settled output Date through the detached worker")
    func reposActivitySubgroupCarriesSettledOutputDate() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repository = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-activity-date"))
            let worktree = try #require(repository.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            atoms.repoCache.setRepoEnrichment(
                .resolvedLocal(
                    repoId: repository.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: repository.name),
                    updatedAt: Date(timeIntervalSince1970: 100_000)
                )
            )
            let referenceDate = Date(timeIntervalSince1970: 100_000)
            let observedAt = referenceDate.addingTimeInterval(-30)
            let preferences = makeProjectionPreferences(atoms: atoms)
            preferences.setSubgroupMode(.activity, for: .repos)
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: preferences,
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { paneID in
                    paneID == pane.id
                        ? PaneActivityStatusFact(lastOutputLine: "tests running", observedAt: observedAt)
                        : nil
                }
            )

            let request = capture.captureRequest(
                query: "",
                referenceDate: referenceDate,
                trigger: .dataRefresh
            )
            let result = try RepoExplorerProjectionWorker.project(request)

            #expect(request.paneRowFactsByPaneId[pane.id]?.activityAt == observedAt)
            #expect(capture.observationTokens(for: request).contains(.paneActivity(pane.id)))
            #expect(
                result.sidebarPresentationTransitionAtByPaneId[pane.id]
                    == observedAt.addingTimeInterval(AppPolicies.RepoExplorer.activeActivityDuration)
            )
            guard case .ready(let content) = result.projection else {
                Issue.record("Expected repository content")
                return
            }
            #expect(content.worktreeRowsByGroupId.values.flatMap { $0 }.first?.activitySubgroup == .active)
        }
    }

    @MainActor
    @Test("system time invalidation refreshes visible demand and defers hidden demand until resume")
    func systemTimeInvalidationRespectsDemandLifecycle() async {
        await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: makeProjectionPreferences(atoms: atoms),
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { _ in nil }
            )
            let dateBox = RepoExplorerRecencyDateBox(Date(timeIntervalSince1970: 100_000))
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                recencyNow: { dateBox.value },
                recencyDelay: AsyncDelay { _ in throw CancellationError() }
            )
            defer { adapter.stop() }
            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<400 where adapter.publishedResult == nil { await Task.yield() }
            let visibleCaptureCount = capture.fullCaptureCount
            dateBox.value = Date(timeIntervalSince1970: 200_000)
            adapter.handleSystemTimeInvalidation()
            for _ in 0..<400 where capture.fullCaptureCount == visibleCaptureCount { await Task.yield() }
            #expect(adapter.cachedProjectionRequest?.snapshot.referenceDate == dateBox.value)

            adapter.updateDemand(isVisible: false, query: "")
            let hiddenCaptureCount = capture.fullCaptureCount
            dateBox.value = Date(timeIntervalSince1970: 300_000)
            adapter.handleSystemTimeInvalidation()
            #expect(capture.fullCaptureCount == hiddenCaptureCount)

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<400 where capture.fullCaptureCount == hiddenCaptureCount { await Task.yield() }
            #expect(adapter.cachedProjectionRequest?.snapshot.referenceDate == dateBox.value)
        }
    }

    @MainActor
    @Test("Panes title change uses keyed capture and full off-main organization projection")
    func panesTitleChangeUsesKeyedCaptureAndFullWorkerProjection() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-pane-keyed-delta"))
            let worktree = try #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "before",
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            atoms.repoCache.setRepoEnrichment(
                .resolvedLocal(
                    repoId: repo.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: repo.name),
                    updatedAt: Date()
                )
            )
            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.repo, for: .panes)
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: preferences,
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { paneID in
                    atoms.paneActivityStatus.status(for: paneID)
                }
            )
            let recorder = RepoExplorerProjectionExecutionRecorder()
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                recencyDelay: AsyncDelay { _ in throw CancellationError() },
                project: { work throws(CancellationError) in
                    recorder.recordExecution(work)
                    do {
                        return try RepoExplorerProjectionWorker.project(work)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        preconditionFailure("Unexpected projection failure: \(error)")
                    }
                }
            )
            defer { adapter.stop() }
            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.publishedRevision < 1 { await Task.yield() }
            #expect(capture.fullCaptureCount == 1)
            #expect(recorder.fullExecutionCount == 1)
            #expect(recorder.deltaExecutionCount == 0)
            store.paneAtom.updatePaneTitle(pane.id, title: "after")
            for _ in 0..<400
            where adapter.publishedResult?.paneRowFactsByPaneId[pane.id]?.terminalTitle != "after" {
                await Task.yield()
            }

            #expect(capture.fullCaptureCount == 1)
            #expect(capture.scopedCaptureCount == 1)
            #expect(recorder.fullExecutionCount == 1)
            #expect(recorder.deltaExecutionCount == 1)
            #expect(adapter.cachedProjectionRequest?.paneRowFactsByPaneId[pane.id]?.terminalTitle == "after")
            #expect(
                adapter.materializedProjection?.latestAcceptedValue?
                    .paneRowFactsByPaneId[pane.id]?.terminalTitle == "after"
            )
            #expect(adapter.publishedResult?.paneRowFactsByPaneId[pane.id]?.terminalTitle == "after")
            #expect(adapter.publishedResult?.projectionDuration != .zero)
        }
    }

}
