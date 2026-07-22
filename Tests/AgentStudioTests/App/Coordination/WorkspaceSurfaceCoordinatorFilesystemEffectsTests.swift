import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorFilesystemEffectsTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("unrelated workspace action performs no filesystem source work")
    func unrelatedWorkspaceActionPerformsNoFilesystemSourceWork() async throws {
        let context = makeContext(named: "unrelated-action")
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let repo = context.store.addRepo(at: context.tempDirectory.appending(path: "repo"))
        let worktree = try #require(context.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let pane = context.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let tab = Tab(paneId: pane.id)
        context.store.appendTab(tab)
        context.store.setActiveTab(tab.id)
        let source = OrderedRecordingFilesystemSource()
        let coordinator = makeCoordinator(context: context, source: source)
        defer { Task { await coordinator.shutdown() } }
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
        await source.resetOperations()

        coordinator.execute(.renameTab(tabId: tab.id, name: "renamed"))
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        #expect(await source.operations().isEmpty)
    }

    @Test("active tab selection writes only the changed active worktree")
    func activeTabSelectionWritesOnlyChangedActiveWorktree() async throws {
        try await withAsyncTestAtomRegistry { _ in
            let context = makeContext(named: "active-selection")
            defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
            let repo = context.store.addRepo(at: context.tempDirectory.appending(path: "repo"))
            let firstWorktree = try #require(context.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
            let secondCandidate = Worktree(
                repoId: repo.id,
                name: "second",
                path: repo.repoPath.appending(path: "second")
            )
            context.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [firstWorktree, secondCandidate])
            let secondWorktree = try #require(
                context.store.repo(repo.id)?.worktrees.first { $0.path == secondCandidate.path }
            )
            let firstPane = context.store.createPane(
                launchDirectory: firstWorktree.path,
                facets: PaneContextFacets(repoId: repo.id, worktreeId: firstWorktree.id, cwd: firstWorktree.path)
            )
            let secondPane = context.store.createPane(
                launchDirectory: secondWorktree.path,
                facets: PaneContextFacets(repoId: repo.id, worktreeId: secondWorktree.id, cwd: secondWorktree.path)
            )
            let firstTab = Tab(paneId: firstPane.id)
            let secondTab = Tab(paneId: secondPane.id)
            context.store.appendTab(firstTab)
            context.store.appendTab(secondTab)
            context.store.setActiveTab(firstTab.id)
            let source = OrderedRecordingFilesystemSource()
            let coordinator = makeCoordinator(context: context, source: source)
            defer { Task { await coordinator.shutdown() } }
            await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
            await source.resetOperations()

            let focusExecutor = PaneFocusExecutor(
                hostViewProvider: { _ in nil },
                hostViewsProvider: { [] },
                selectTab: { context.store.setActiveTab($0) },
                selectPane: { _, _ in },
                selectDrawerPane: { _, _ in },
                selectEmptyDrawer: { _ in },
                syncRuntimeFocus: { _ in }
            )
            let focusDecision = PaneCommandFocusDecider.decide(
                trigger: .selectTab(secondTab.id),
                context: PaneFocusContext(
                    activeTabId: firstTab.id,
                    activePaneId: firstPane.id,
                    activeDrawer: nil,
                    targetPaneId: secondPane.id,
                    targetTabId: secondTab.id,
                    targetPaneKind: .terminal,
                    targetPaneIsAlreadyActive: false,
                    targetMountedContent: .unmounted,
                    managementLayer: .inactive,
                    windowState: .key
                )
            )
            focusExecutor.apply(.command(focusDecision))
            await source.waitForOperationCount(1)
            await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

            #expect(await source.operations() == [.activePane(worktreeId: secondWorktree.id)])
        }
    }

    @Test("direct worktree open writes only the changed active worktree")
    func directWorktreeOpenWritesOnlyChangedActiveWorktree() async throws {
        let context = makeContext(named: "direct-open")
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let repo = context.store.addRepo(at: context.tempDirectory.appending(path: "repo"))
        let firstWorktree = try #require(context.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let secondCandidate = Worktree(
            repoId: repo.id,
            name: "second",
            path: repo.repoPath.appending(path: "second")
        )
        context.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [firstWorktree, secondCandidate])
        let secondWorktree = try #require(
            context.store.repo(repo.id)?.worktrees.first { $0.path == secondCandidate.path }
        )
        let firstPane = context.store.createPane(
            launchDirectory: firstWorktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: firstWorktree.id, cwd: firstWorktree.path)
        )
        let secondPane = context.store.createPane(
            launchDirectory: secondWorktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: secondWorktree.id, cwd: secondWorktree.path)
        )
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        context.store.appendTab(firstTab)
        context.store.appendTab(secondTab)
        context.store.setActiveTab(firstTab.id)
        let source = OrderedRecordingFilesystemSource()
        let coordinator = makeCoordinator(context: context, source: source)
        defer { Task { await coordinator.shutdown() } }
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
        await source.resetOperations()

        _ = coordinator.openTerminal(for: secondWorktree, in: repo)
        await source.waitForOperationCount(1)
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        #expect(await source.operations() == [.activePane(worktreeId: secondWorktree.id)])
    }

    @Test("surface CWD change updates only old and new activity plus active worktree")
    func surfaceCWDChangeUpdatesOnlyAffectedKeys() async throws {
        let context = makeContext(named: "cwd-effect")
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let repo = context.store.addRepo(at: context.tempDirectory.appending(path: "repo"))
        let firstWorktree = try #require(context.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let secondCandidate = Worktree(
            repoId: repo.id,
            name: "second",
            path: repo.repoPath.appending(path: "second")
        )
        context.store.reconcileDiscoveredWorktrees(repo.id, worktrees: [firstWorktree, secondCandidate])
        let secondWorktree = try #require(
            context.store.repo(repo.id)?.worktrees.first { $0.path == secondCandidate.path }
        )
        let pane = context.store.createPane(
            launchDirectory: firstWorktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: firstWorktree.id, cwd: firstWorktree.path)
        )
        let tab = Tab(paneId: pane.id)
        context.store.appendTab(tab)
        context.store.setActiveTab(tab.id)
        let source = OrderedRecordingFilesystemSource()
        let surfaceManager = MockFilesystemCoordinatorSurfaceManager()
        let coordinator = makeCoordinator(context: context, source: source, surfaceManager: surfaceManager)
        defer { Task { await coordinator.shutdown() } }
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
        await source.resetOperations()

        surfaceManager.sendCWDChange(paneId: pane.id, cwd: secondWorktree.path)
        await source.waitForOperationCount(3)
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        #expect(
            await source.operations() == [
                .activity(worktreeId: firstWorktree.id, isActiveInApp: false),
                .activity(worktreeId: secondWorktree.id, isActiveInApp: true),
                .activePane(worktreeId: secondWorktree.id),
            ]
        )
    }

    @Test("pane mount and removal write only affected worktree activity")
    func paneMountAndRemovalWriteOnlyAffectedActivity() async throws {
        let context = makeContext(named: "pane-lifecycle")
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let repo = context.store.addRepo(at: context.tempDirectory.appending(path: "repo"))
        let worktree = try #require(context.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let source = OrderedRecordingFilesystemSource()
        let coordinator = makeCoordinator(context: context, source: source)
        defer { Task { await coordinator.shutdown() } }
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
        await source.resetOperations()

        let pane = context.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        coordinator.upsertPaneFilesystemProjectionContext(for: pane)
        await source.waitForOperationCount(1)
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
        #expect(await source.operations() == [.activity(worktreeId: worktree.id, isActiveInApp: true)])

        await source.resetOperations()
        coordinator.removePaneFilesystemProjectionContext(paneId: pane.id)
        await source.waitForOperationCount(1)
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
        #expect(await source.operations() == [.activity(worktreeId: worktree.id, isActiveInApp: false)])
    }

    @Test("failed current mount and failed insertion leave no filesystem membership")
    func failedMountAndInsertionLeaveNoFilesystemMembership() async throws {
        let context = makeContext(named: "failed-mount")
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let repo = context.store.addRepo(at: context.tempDirectory.appending(path: "repo"))
        let worktree = try #require(context.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let pane = context.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let source = OrderedRecordingFilesystemSource()
        let coordinator = makeCoordinator(context: context, source: source)
        defer { Task { await coordinator.shutdown() } }
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()
        await source.resetOperations()

        let mountedView = coordinator.mountCurrentTerminalContent(
            pane: pane,
            initialFrame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        coordinator.executeInsertPane(
            source: .newTerminal,
            targetTabId: UUID(),
            targetPaneId: UUID(),
            direction: .right,
            sizingMode: .halveTarget
        )
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        #expect(mountedView == nil)
        #expect(await source.operations().isEmpty)
    }

    @Test("accepted pane effects request one trace identity fleet capture per drain")
    func acceptedPaneEffectsRequestOneTraceIdentityFleetCapturePerDrain() async throws {
        let context = makeContext(named: "trace-identity")
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let repo = context.store.addRepo(at: context.tempDirectory.appending(path: "repo"))
        let worktree = try #require(context.store.repo(repo.id)?.worktrees.first { $0.isMainWorktree })
        let pane = context.store.createPane(
            launchDirectory: worktree.path,
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        )
        let source = OrderedRecordingFilesystemSource()
        let traceIdentityRecorder = TraceIdentityFleetCaptureRecorder()
        let coordinator = makeCoordinator(
            context: context,
            source: source,
            traceIdentityRefreshHandler: { traceIdentityRecorder.recordFleetCapture() }
        )
        defer { Task { await coordinator.shutdown() } }
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        coordinator.upsertPaneFilesystemProjectionContext(for: pane)
        coordinator.upsertPaneFilesystemProjectionContext(for: pane)
        await coordinator.waitForFilesystemRootsAndActivitySyncIdle()

        #expect(traceIdentityRecorder.fleetCaptureCount == 1)
    }

    private func makeContext(named name: String) -> FilesystemEffectsTestContext {
        FilesystemEffectsTestContext(
            store: WorkspaceStore(),
            bus: makeTestPaneRuntimeEventBus(),
            tempDirectory: FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-filesystem-effects-\(name)-\(UUID().uuidString)")
        )
    }

    private func makeCoordinator(
        context: FilesystemEffectsTestContext,
        source: OrderedRecordingFilesystemSource,
        surfaceManager: WorkspaceSurfaceManaging = MockFilesystemCoordinatorSurfaceManager(),
        traceIdentityRefreshHandler: (@MainActor @Sendable () -> Void)? = nil
    ) -> WorkspaceSurfaceCoordinator {
        WorkspaceSurfaceCoordinator(
            store: context.store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: context.store),
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: context.bus,
            filesystemSource: source,
            filesystemProjectionIndex: FilesystemProjectionIndex(),
            windowLifecycleStore: WindowLifecycleAtom(),
            traceIdentityRefreshHandler: traceIdentityRefreshHandler
        )
    }
}

@MainActor
private struct FilesystemEffectsTestContext {
    let store: WorkspaceStore
    let bus: EventBus<RuntimeEnvelope>
    let tempDirectory: URL
}

@MainActor
private final class TraceIdentityFleetCaptureRecorder {
    private(set) var fleetCaptureCount = 0

    func recordFleetCapture() {
        fleetCaptureCount += 1
    }
}
