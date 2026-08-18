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
    @Test("mixed capability and visible-set wake re-resolves surviving requests")
    func mixedCapabilityAndVisibleSetWakeReresolvesSurvivingRequests() async throws {
        let handler = RepoExplorerCommandPresentationRecordingHandler()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                await withAsyncTestCoreAtoms { coreAtoms in
                    coreAtoms.managementLayer.deactivate()
                    defer { coreAtoms.managementLayer.deactivate() }

                    let store = WorkspaceStore()
                    let firstRepo = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-mixed-first-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    let secondRepo = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-mixed-second-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    let firstWorktree = try! #require(firstRepo.worktrees.first)
                    let secondWorktree = try! #require(secondRepo.worktrees.first)
                    let visibleWorktrees = SidebarVisibleWorktreesRuntimeAtom()
                    visibleWorktrees.setVisibleWorktreeIds([firstWorktree.id])
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        visibleWorktrees: visibleWorktrees,
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }

                    _ = await handler.batchArrivals.wait { _ in true }
                    handler.repoExplorerCapabilityRequestBatches.removeAll()

                    coreAtoms.managementLayer.toggle()
                    visibleWorktrees.setVisibleWorktreeIds([firstWorktree.id, secondWorktree.id])

                    _ = await handler.batchArrivals.wait { requests in
                        requests.contains { request in
                            request.target == secondWorktree.id
                        }
                    }
                    let resolvedRequests = try! #require(
                        handler.repoExplorerCapabilityRequestBatches.first { requests in
                            requests.contains { request in
                                request.target == secondWorktree.id
                            }
                        }
                    )
                    let expectedRequests = RepoExplorerToolbarCommandPresentation.requests(
                        nextSortOrder: .default.toggled
                    ).union(
                        RepoExplorerWorktreeCommandPresentation.requests(
                            worktreeId: firstWorktree.id,
                            repoId: firstRepo.id,
                            isFavorite: firstRepo.isFavorite,
                            showsFavoriteControl: firstWorktree.isMainWorktree
                        )
                    ).union(
                        RepoExplorerWorktreeCommandPresentation.requests(
                            worktreeId: secondWorktree.id,
                            repoId: secondRepo.id,
                            isFavorite: secondRepo.isFavorite,
                            showsFavoriteControl: secondWorktree.isMainWorktree
                        )
                    )
                    #expect(resolvedRequests == expectedRequests)
                }
            }
        )
    }

    @Test("visible-set delta resolves only newly visible worktree requests")
    func visibleSetDeltaResolvesOnlyNewlyVisibleWorktreeRequests() async throws {
        let handler = RepoExplorerCommandPresentationRecordingHandler()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                await withAsyncTestCoreAtoms { _ in
                    let store = WorkspaceStore()
                    let firstRepo = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-first-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    let secondRepo = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-second-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    let firstWorktree = try! #require(firstRepo.worktrees.first)
                    let secondWorktree = try! #require(secondRepo.worktrees.first)
                    let visibleWorktrees = SidebarVisibleWorktreesRuntimeAtom()
                    visibleWorktrees.setVisibleWorktreeIds([firstWorktree.id])
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        visibleWorktrees: visibleWorktrees,
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }

                    _ = await handler.batchArrivals.wait { _ in true }
                    handler.repoExplorerCapabilityRequestBatches.removeAll()

                    visibleWorktrees.setVisibleWorktreeIds([firstWorktree.id, secondWorktree.id])

                    _ = await handler.batchArrivals.wait { requests in
                        requests.contains { request in
                            request.target == secondWorktree.id
                        }
                    }
                    let resolvedRequests = try! #require(
                        handler.repoExplorerCapabilityRequestBatches.first { requests in
                            requests.contains { request in
                                request.target == secondWorktree.id
                            }
                        }
                    )
                    let expectedRequests = RepoExplorerWorktreeCommandPresentation.requests(
                        worktreeId: secondWorktree.id,
                        repoId: secondRepo.id,
                        isFavorite: secondRepo.isFavorite,
                        showsFavoriteControl: secondWorktree.isMainWorktree
                    )
                    #expect(resolvedRequests == expectedRequests)
                }
            }
        )
    }

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
            try await recorder.drain()

            let outputFileURL = try #require(runtime.outputFileURL)
            let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
            #expect(contents.contains("\"body\":\"performance.repo_explorer.command_presentation\""))
            #expect(
                contents.contains(
                    "\"agentstudio.performance.repo_explorer.command_resolution.count\":\(expectedResolutionCount)"
                )
            )
            #expect(
                contents.contains(
                    "\"agentstudio.performance.repo_explorer.visible_set.count\":0"
                )
            )
            #expect(
                contents.contains(
                    "\"agentstudio.performance.repo_explorer.visible_set_delta.count\":0"
                )
            )
            #expect(
                contents.contains(
                    "\"agentstudio.performance.repo_explorer.command_reused.count\":0"
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
                    let secondPane = store.createPane()
                    store.appendTab(Tab(paneId: secondPane.id))
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

                    let activeTabGeneration = managementGeneration
                    let presentationBeforeUnrelatedRepo = batch.snapshot.results
                    let capabilityBatchCountBeforeUnrelatedRepo =
                        replacementHandler.repoExplorerCapabilityRequestBatches.count

                    _ = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-batch-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    for _ in 0..<20 { await Task.yield() }
                    #expect(batch.snapshot.generation == activeTabGeneration)
                    #expect(batch.snapshot.results == presentationBeforeUnrelatedRepo)
                    #expect(
                        replacementHandler.repoExplorerCapabilityRequestBatches.count
                            == capabilityBatchCountBeforeUnrelatedRepo
                    )
                }
            }
        )
    }

    @Test("active tab recomputes capability without changing equal presentation")
    func activeTabRecomputesCapabilityWithoutChangingEqualPresentation() async throws {
        let handler = RepoExplorerCommandPresentationRecordingHandler()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                await withAsyncTestCoreAtoms { _ in
                    let store = WorkspaceStore()
                    let firstPane = store.createPane()
                    store.appendTab(Tab(paneId: firstPane.id))
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        visibleWorktrees: SidebarVisibleWorktreesRuntimeAtom(),
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }

                    _ = await handler.batchArrivals.wait { _ in true }
                    let initialGeneration = batch.snapshot.generation
                    handler.repoExplorerCapabilityRequestBatches.removeAll()

                    let secondPane = store.createPane()
                    store.appendTab(Tab(paneId: secondPane.id))

                    _ = await handler.batchArrivals.wait { _ in true }
                    #expect(!handler.repoExplorerCapabilityRequestBatches.isEmpty)
                    #expect(batch.snapshot.generation == initialGeneration)
                }
            }
        )
    }

    @Test("association move resolves only affected visible worktree rows")
    func associationMoveResolvesOnlyAffectedVisibleWorktreeRows() async throws {
        let handler = RepoExplorerCommandPresentationRecordingHandler()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                await withAsyncTestCoreAtoms { _ in
                    let store = WorkspaceStore()
                    let repos = (0..<3).map { index in
                        store.addRepo(
                            at: FileManager.default.temporaryDirectory.appending(
                                path: "repo-command-association-\(index)-\(UUIDv7.generate().uuidString)"
                            )
                        )
                    }
                    let worktrees = repos.compactMap(\.worktrees.first)
                    guard worktrees.count == 3 else {
                        Issue.record("expected three worktrees")
                        return
                    }
                    let pane = store.createPane(
                        launchDirectory: worktrees[0].path,
                        facets: PaneContextFacets(
                            repoId: repos[0].id,
                            worktreeId: worktrees[0].id,
                            cwd: worktrees[0].path
                        )
                    )
                    store.appendTab(Tab(paneId: pane.id))
                    let visibleWorktrees = SidebarVisibleWorktreesRuntimeAtom()
                    visibleWorktrees.setVisibleWorktreeIds(Set(worktrees.map(\.id)))
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        visibleWorktrees: visibleWorktrees,
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }

                    _ = await handler.batchArrivals.wait { _ in true }
                    handler.repoExplorerCapabilityRequestBatches.removeAll()

                    _ = store.paneAtom.updatePaneCWDAndResolvedContext(
                        pane.id,
                        cwd: worktrees[1].path,
                        resolvedContext: (repos[1], worktrees[1])
                    )

                    let affectedRequests = await handler.batchArrivals.wait { requests in
                        requests.contains { $0.target == worktrees[1].id }
                    }
                    #expect(affectedRequests.contains { $0.target == worktrees[0].id })
                    #expect(affectedRequests.contains { $0.target == worktrees[1].id })
                    #expect(!affectedRequests.contains { $0.target == worktrees[2].id })
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

@MainActor
private final class RepoExplorerCommandPresentationRecordingHandler: WorkspaceCommandHandling {
    let batchArrivals = ExactEventAcknowledgement<Set<RepoExplorerCommandPresentationRequest>>()
    var repoExplorerCapabilityRequestBatches: [Set<RepoExplorerCommandPresentationRequest>] = []

    func execute(_: AppCommand) {}

    func execute(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}

    func canExecute(_: AppCommand) -> Bool {
        true
    }

    func executeExtractPaneToTab(tabId _: UUID, paneId _: UUID, targetTabInsertionIndex _: Int?) {}

    func executeMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}

    func repoExplorerCommandCapabilities(
        _ requests: Set<RepoExplorerCommandPresentationRequest>
    ) -> [RepoExplorerCommandPresentationRequest: Bool] {
        repoExplorerCapabilityRequestBatches.append(requests)
        batchArrivals.record(requests)
        return Dictionary(uniqueKeysWithValues: requests.map { ($0, true) })
    }
}
