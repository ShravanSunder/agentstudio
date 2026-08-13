import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repo Explorer command presentation batch", .serialized)
struct RepoExplorerCommandPresentationBatchTests {
    @Test("accepted batch records bounded command presentation work")
    func acceptedBatchRecordsBoundedCommandPresentationWork() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let traceDirectory = FileManager.default.temporaryDirectory.appending(
                path: "repo-command-presentation-trace-\(UUIDv7.generate().uuidString)"
            )
            defer { try? FileManager.default.removeItem(at: traceDirectory) }
            let runtime = AgentStudioTraceRuntime(
                configuration: AgentStudioTraceConfiguration.from(environment: [
                    "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                    "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                    "AGENTSTUDIO_TRACE_NAME": "repo-command-presentation-batch",
                    "AGENTSTUDIO_TRACE_TAGS": "performance",
                ]),
                processIdentifier: 931,
                timeUnixNano: { 931 }
            )
            let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
            let store = WorkspaceStore()
            let visibleWorktrees = SidebarVisibleWorktreesRuntimeAtom()
            visibleWorktrees.setVisibleWorktreeIds([])
            let expectedResolutionCount = RepoExplorerToolbarCommandPresentation.requests(
                nextSortOrder: .default.toggled
            ).count
            let batch = RepoExplorerCommandPresentationBatch(
                store: store,
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                visibleWorktrees: visibleWorktrees,
                dispatcher: .shared,
                performanceTraceRecorder: recorder
            )

            batch.start()
            defer { batch.stop() }
            await eventually("initial command presentation batch") {
                batch.snapshot.generation == 1
            }
            let expectedAffectedItemCount = batch.snapshot.results.count
            try await recorder.drain()

            let outputFileURL = try #require(runtime.outputFileURL)
            let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
            #expect(contents.contains("\"body\":\"performance.repo_explorer.command_presentation\""))
            #expect(
                contents.contains(
                    "\"agentstudio.performance.repo_explorer.affected_item.count\":\(expectedAffectedItemCount)"
                )
            )
            #expect(
                contents.contains(
                    "\"agentstudio.performance.repo_explorer.command_resolution.count\":\(expectedResolutionCount)"
                )
            )
            #expect(
                contents.contains(
                    "\"agentstudio.performance.repo_explorer.capability_snapshot.count\":1"
                )
            )
        }
    }

    @Test("batch resolves targeted requests once and live dispatch can reject a stale enabled result")
    func batchIsAdvisoryAndLiveDispatchRevalidates() async throws {
        let handler = MockCommandHandler()
        handler.targetedCanExecuteResult = true
        let worktreeId = UUIDv7.generate()
        let requests = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: worktreeId,
            repoId: UUIDv7.generate(),
            isFavorite: false,
            showsFavoriteControl: true
        )

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                let snapshot = AppCommandDispatcher.shared.repoExplorerCommandPresentationSnapshot(
                    requests: requests,
                    generation: 4
                )
                let openRequest = requests.first { request in
                    request.command == .openWorktree && request.surface == .inlineControl
                }!
                #expect(snapshot.generation == 4)
                #expect(snapshot.results[openRequest] == true)

                handler.targetedCanExecuteResult = false
                AppCommandDispatcher.shared.dispatch(
                    .openWorktree,
                    target: worktreeId,
                    targetType: .worktree
                )

                #expect(handler.executedCommands.isEmpty)
            }
        )
    }

    @Test("capability recompute preserves presentation for structural facts outside the visible worktree set")
    func capabilityRecomputePreservesPresentationForUnrelatedStructuralFacts() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = nil
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                await withAsyncTestCoreAtoms { coreAtoms in
                    coreAtoms.managementLayer.deactivate()
                    defer { coreAtoms.managementLayer.deactivate() }

                    let store = WorkspaceStore()
                    let visibleWorktrees = SidebarVisibleWorktreesRuntimeAtom()
                    let prefs = RepoExplorerSidebarPrefsAtom()
                    let pane = store.createPane()
                    let tab = Tab(paneId: pane.id)
                    store.appendTab(tab)
                    visibleWorktrees.setVisibleWorktreeIds([])

                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: prefs,
                        visibleWorktrees: visibleWorktrees,
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }

                    await eventually("initial command presentation generation") {
                        batch.snapshot.generation > 0
                    }
                    let initialGeneration = batch.snapshot.generation

                    let replacementHandler = MockCommandHandler()
                    replacementHandler.canExecuteResult = false
                    replacementHandler.targetedCanExecuteResult = false
                    AppCommandDispatcher.shared.handler = replacementHandler
                    for _ in 0..<20 {
                        await Task.yield()
                    }
                    #expect(batch.snapshot.generation == initialGeneration)

                    store.paneAtom.updatePaneTitle(pane.id, title: "quiet title")
                    for _ in 0..<20 {
                        await Task.yield()
                    }
                    #expect(batch.snapshot.generation == initialGeneration)

                    coreAtoms.managementLayer.toggle()
                    await eventually("management capability generation") {
                        batch.snapshot.generation > initialGeneration
                    }
                    let managementGeneration = batch.snapshot.generation

                    store.panePresentationAtom.enterZoom(
                        inTab: tab.id,
                        sourcePaneId: pane.id,
                        viewerPresentation: .unavailable
                    )
                    for _ in 0..<20 { await Task.yield() }
                    #expect(batch.snapshot.generation == managementGeneration)

                    let secondPane = store.createPane()
                    store.appendTab(Tab(paneId: secondPane.id))
                    await eventually("active tab capability generation") {
                        batch.snapshot.generation > managementGeneration
                    }
                    let activeTabGeneration = batch.snapshot.generation
                    let presentationBeforeUnrelatedRepo = batch.snapshot.results

                    _ = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-batch-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    // A path-index rebuild is uncertain for any pane CWD, so recomputation is
                    // required even when equality suppresses a visible presentation change.
                    await eventually("path index capability recompute") {
                        batch.snapshot.generation > activeTabGeneration
                    }
                    #expect(batch.snapshot.results == presentationBeforeUnrelatedRepo)
                }
            }
        )
    }

    @Test("drawer changes outside the visible worktree set stay quiet")
    func unrelatedDrawerVisibilityStaysQuiet() async {
        await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let pane = store.createPane()
            store.appendTab(Tab(paneId: pane.id))
            let batch = RepoExplorerCommandPresentationBatch(
                store: store,
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                visibleWorktrees: SidebarVisibleWorktreesRuntimeAtom(),
                dispatcher: .shared
            )
            batch.start()
            defer { batch.stop() }

            await eventually("initial drawer capability generation") {
                batch.snapshot.generation > 0
            }
            let collapsedGeneration = batch.snapshot.generation
            #expect(store.paneAtom.isDrawerExpanded(for: pane.id) == false)

            store.toggleDrawer(for: pane.id)
            for _ in 0..<20 { await Task.yield() }
            #expect(batch.snapshot.generation == collapsedGeneration)
            #expect(store.paneAtom.isDrawerExpanded(for: pane.id) == true)

            store.toggleDrawer(for: pane.id)
            for _ in 0..<20 { await Task.yield() }
            #expect(batch.snapshot.generation == collapsedGeneration)
            #expect(store.paneAtom.isDrawerExpanded(for: pane.id) == false)
        }
    }
}
