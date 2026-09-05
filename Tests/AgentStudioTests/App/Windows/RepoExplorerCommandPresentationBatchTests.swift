import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repo Explorer command presentation batch", .serialized)
struct RepoExplorerCommandPresentationBatchTests {
    @Test("keyed repository progress re-resolves only the visible update control")
    func keyedRepositoryProgressReresolvesVisibleUpdateControl() async throws {
        let handler = RepoExplorerCommandPresentationRecordingHandler()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                try await withAsyncTestCoreAtoms { coreAtoms in
                    let traceDirectory = FileManager.default.temporaryDirectory.appending(
                        path: "repo-command-progress-trace-\(UUIDv7.generate().uuidString)"
                    )
                    defer { try? FileManager.default.removeItem(at: traceDirectory) }
                    let runtime = AgentStudioTraceRuntime(
                        configuration: AgentStudioTraceConfiguration.from(environment: [
                            "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                            "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                            "AGENTSTUDIO_TRACE_NAME": "repo-command-progress-trace",
                            "AGENTSTUDIO_TRACE_TAGS": "performance",
                        ]),
                        processIdentifier: 933,
                        timeUnixNano: { 933 }
                    )
                    let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
                    let store = WorkspaceStore()
                    let repository = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-progress-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    let request = RepoExplorerRepositoryCommandPresentation.request(
                        repoID: repository.id
                    )
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        dispatcher: .shared,
                        performanceTraceRecorder: recorder
                    )
                    batch.start()
                    defer { batch.stop() }
                    batch.acceptVisibleWorktreeSnapshot(
                        makeVisibleWorktreeSnapshot(
                            worktreeIDs: [],
                            repositoryIDs: [repository.id]
                        )
                    )

                    _ = await handler.batchArrivals.wait { $0.contains(request) }
                    #expect(batch.snapshot.results[request] == true)
                    handler.repoExplorerCapabilityRequestBatches.removeAll()
                    handler.capabilityResult = false
                    coreAtoms.repoCache.setRepositoryFactUpdateProgress(
                        .captured(repoId: repository.id, attemptId: UUIDv7.generate())
                    )

                    let progressRequests = await handler.batchArrivals.wait { requests in
                        requests.contains(request) && requests.count == 1
                    }
                    #expect(progressRequests == [request])
                    #expect(batch.snapshot.results[request] == false)
                    #expect(batch.latestDelta?.affectedRepositoryIDs == [repository.id])
                    #expect(batch.latestDelta?.affectedWorktreeIDs.isEmpty == true)

                    try await recorder.drain()
                    let outputFileURL = try #require(runtime.outputFileURL)
                    let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
                    let visibleSnapshotTriggerCount = contents.split(separator: "\n").count { line in
                        line.contains("\"body\":\"performance.repo_explorer.command_presentation\"")
                            && line.contains(
                                "\"agentstudio.performance.repo_explorer.wake_trigger\":\"visible_snapshot\""
                            )
                    }
                    let observationTriggerCount = contents.split(separator: "\n").count { line in
                        line.contains("\"body\":\"performance.repo_explorer.command_presentation\"")
                            && line.contains(
                                "\"agentstudio.performance.repo_explorer.wake_trigger\":\"observation\""
                            )
                    }
                    #expect(visibleSnapshotTriggerCount >= 1)
                    #expect(observationTriggerCount >= 1)
                }
            }
        )
    }

    @Test("stale observation trackings do not multiply refreshes")
    func staleObservationTrackingsDoNotMultiplyRefreshes() async throws {
        let handler = RepoExplorerCommandPresentationRecordingHandler()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = handler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                try await withAsyncTestCoreAtoms { coreAtoms in
                    let traceDirectory = FileManager.default.temporaryDirectory.appending(
                        path: "repo-command-stale-tracking-trace-\(UUIDv7.generate().uuidString)"
                    )
                    defer { try? FileManager.default.removeItem(at: traceDirectory) }
                    let runtime = AgentStudioTraceRuntime(
                        configuration: AgentStudioTraceConfiguration.from(environment: [
                            "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                            "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                            "AGENTSTUDIO_TRACE_NAME": "repo-command-stale-tracking-trace",
                            "AGENTSTUDIO_TRACE_TAGS": "performance",
                        ]),
                        processIdentifier: 933,
                        timeUnixNano: { 933 }
                    )
                    let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
                    let store = WorkspaceStore()
                    let repository = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-stale-tracking-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    let request = RepoExplorerRepositoryCommandPresentation.request(
                        repoID: repository.id
                    )
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        dispatcher: .shared,
                        performanceTraceRecorder: recorder
                    )
                    batch.start()
                    defer { batch.stop() }

                    for revision in 1...25 {
                        batch.acceptVisibleWorktreeSnapshot(
                            makeVisibleWorktreeSnapshot(
                                worktreeIDs: [],
                                repositoryIDs: [repository.id],
                                visibleRevision: UInt64(revision)
                            )
                        )
                    }

                    _ = await handler.batchArrivals.wait { $0.contains(request) }
                    handler.repoExplorerCapabilityRequestBatches.removeAll()

                    try await recorder.flush()
                    let outputFileURL = try #require(runtime.outputFileURL)
                    let observationBefore = try String(contentsOf: outputFileURL, encoding: .utf8)
                        .split(separator: "\n")
                        .count { line in
                            line.contains("\"body\":\"performance.repo_explorer.command_presentation\"")
                                && line.contains(
                                    "\"agentstudio.performance.repo_explorer.wake_trigger\":\"observation\""
                                )
                        }

                    coreAtoms.repoCache.setRepositoryFactUpdateProgress(
                        .captured(repoId: repository.id, attemptId: UUIDv7.generate())
                    )

                    _ = await handler.batchArrivals.wait { $0.contains(request) }
                    for _ in 0..<2000 { await Task.yield() }

                    try await recorder.drain()
                    let observationAfter = try String(contentsOf: outputFileURL, encoding: .utf8)
                        .split(separator: "\n")
                        .count { line in
                            line.contains("\"body\":\"performance.repo_explorer.command_presentation\"")
                                && line.contains(
                                    "\"agentstudio.performance.repo_explorer.wake_trigger\":\"observation\""
                                )
                        }

                    #expect(observationAfter - observationBefore == 1)
                }
            }
        )
    }

    @Test("equal command results retarget to a newer native materialization target")
    func equalCommandResultsRetargetToNewerNativeTarget() async throws {
        await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repo = store.addRepo(
                at: FileManager.default.temporaryDirectory.appending(
                    path: "repo-command-retarget-\(UUIDv7.generate().uuidString)"
                )
            )
            let worktree = try! #require(repo.worktrees.first)
            let batch = RepoExplorerCommandPresentationBatch(
                store: store,
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                dispatcher: .shared
            )
            batch.start()
            defer { batch.stop() }
            let initialVisibleSnapshot = makeVisibleWorktreeSnapshot(
                worktreeIDs: [worktree.id],
                visibleRevision: 1
            )
            batch.acceptVisibleWorktreeSnapshot(initialVisibleSnapshot)
            await eventually("initial command delta") {
                batch.latestDelta != nil
            }
            let initialDelta = try! #require(batch.latestDelta)
            let target = RepoExplorerCommandPresentationTarget(
                materializationHostLifetimeID: initialVisibleSnapshot.target.materializationHostLifetimeID,
                materializationGeneration: 2,
                visibleRevision: 4
            )

            batch.acceptVisibleWorktreeSnapshot(
                RepoExplorerVisibleWorktreeSnapshot(
                    target: target,
                    worktreeIDs: [worktree.id]
                )
            )

            await eventually("retargeted equal command delta") {
                batch.latestDelta?.target == target
            }
            let retargetedDelta = try! #require(batch.latestDelta)
            #expect(retargetedDelta.commandGeneration > initialDelta.commandGeneration)
            #expect(retargetedDelta.snapshot.results == initialDelta.snapshot.results)
            #expect(retargetedDelta.affectedWorktreeIDs == [worktree.id])
        }
    }

    @Test("favorite transition includes both old and new request identities")
    func favoriteTransitionIncludesOldAndNewRequestIdentities() async throws {
        await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let repo = store.addRepo(
                at: FileManager.default.temporaryDirectory.appending(
                    path: "repo-command-favorite-union-\(UUIDv7.generate().uuidString)"
                )
            )
            let worktree = try! #require(repo.worktrees.first)
            let batch = RepoExplorerCommandPresentationBatch(
                store: store,
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                dispatcher: .shared
            )
            batch.start()
            defer { batch.stop() }
            batch.acceptVisibleWorktreeSnapshot(
                makeVisibleWorktreeSnapshot(worktreeIDs: [worktree.id])
            )
            await eventually("initial favorite command delta") {
                batch.latestDelta != nil
            }

            store.mutationCoordinator.setRepoFavorite(repo.id, isFavorite: true)

            await eventually("favorite command identity transition") {
                batch.latestDelta?.affectedRequestIdentities.contains { request in
                    request.command == .removeRepoFavorite
                } == true
            }
            let delta = try! #require(batch.latestDelta)
            #expect(
                delta.affectedRequestIdentities.contains { request in
                    request.command == .addRepoFavorite
                        && request.target == repo.id
                }
            )
            #expect(
                delta.affectedRequestIdentities.contains { request in
                    request.command == .removeRepoFavorite
                        && request.target == repo.id
                }
            )
            #expect(delta.affectedRepositoryIDs == [repo.id])
            #expect(delta.affectedWorktreeIDs == [worktree.id])
        }
    }

    @Test("toolbar capability requests keep both sort destinations mounted")
    func toolbarCapabilityRequestsKeepBothSortDestinationsMounted() {
        let requestsBeforeToggle = RepoExplorerToolbarCommandPresentation.requests(
            nextSortOrder: .descending
        )
        let requestsAfterToggle = RepoExplorerToolbarCommandPresentation.requests(
            nextSortOrder: .ascending
        )
        let requestedSortOrders = Set(
            requestsBeforeToggle.compactMap { request -> RepoExplorerSortOrder? in
                guard case .repoSidebarSortOrder(let order) = request.arguments else { return nil }
                return order
            }
        )

        #expect(requestsBeforeToggle == requestsAfterToggle)
        #expect(requestedSortOrders == Set(RepoExplorerSortOrder.allCases))
    }

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
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }
                    let initialVisibleSnapshot = makeVisibleWorktreeSnapshot(
                        worktreeIDs: [firstWorktree.id]
                    )
                    batch.acceptVisibleWorktreeSnapshot(initialVisibleSnapshot)

                    _ = await handler.batchArrivals.wait { _ in true }
                    handler.repoExplorerCapabilityRequestBatches.removeAll()

                    coreAtoms.managementLayer.toggle()
                    batch.acceptVisibleWorktreeSnapshot(
                        makeVisibleWorktreeSnapshot(
                            hostLifetimeID: initialVisibleSnapshot.target.materializationHostLifetimeID,
                            worktreeIDs: [firstWorktree.id, secondWorktree.id],
                            visibleRevision: 2
                        )
                    )

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
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }
                    let initialVisibleSnapshot = makeVisibleWorktreeSnapshot(
                        worktreeIDs: [firstWorktree.id]
                    )
                    batch.acceptVisibleWorktreeSnapshot(initialVisibleSnapshot)

                    _ = await handler.batchArrivals.wait { _ in true }
                    handler.repoExplorerCapabilityRequestBatches.removeAll()

                    batch.acceptVisibleWorktreeSnapshot(
                        makeVisibleWorktreeSnapshot(
                            hostLifetimeID: initialVisibleSnapshot.target.materializationHostLifetimeID,
                            worktreeIDs: [firstWorktree.id, secondWorktree.id],
                            visibleRevision: 2
                        )
                    )

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
            let expectedResolutionCount = RepoExplorerToolbarCommandPresentation.requests(
                nextSortOrder: .default.toggled
            ).count
            let batch = RepoExplorerCommandPresentationBatch(
                store: store,
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                dispatcher: .shared,
                performanceTraceRecorder: recorder
            )

            batch.start()
            defer { batch.stop() }
            batch.acceptVisibleWorktreeSnapshot(
                makeVisibleWorktreeSnapshot(worktreeIDs: [])
            )
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
                    let prefs = RepoExplorerSidebarPrefsAtom()
                    let visibleRepo = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-visible-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    let visibleWorktree = try! #require(visibleRepo.worktrees.first)
                    let pane = store.createPane()
                    let tab = Tab(paneId: pane.id)
                    store.appendTab(tab)
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: prefs,
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }
                    batch.acceptVisibleWorktreeSnapshot(
                        makeVisibleWorktreeSnapshot(worktreeIDs: [visibleWorktree.id])
                    )

                    await eventually("initial command presentation generation") {
                        batch.snapshot.generation > 0
                    }
                    let initialGeneration = batch.snapshot.generation

                    let replacementHandler = MockCommandHandler()
                    replacementHandler.canExecuteResult = false
                    replacementHandler.targetedCanExecuteResult = false
                    AppCommandDispatcher.shared.handler = replacementHandler
                    let ownedCapabilityBatchCount = {
                        replacementHandler.repoExplorerCapabilityRequestBatches.filter { requests in
                            requests.contains { request in
                                request.target == visibleWorktree.id
                            }
                        }.count
                    }
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

                    let ownedCapabilityBatchCountBeforeActiveTab = ownedCapabilityBatchCount()
                    let secondPane = store.createPane()
                    store.appendTab(Tab(paneId: secondPane.id))
                    await eventually("active tab capability recompute") {
                        ownedCapabilityBatchCount() > ownedCapabilityBatchCountBeforeActiveTab
                    }
                    #expect(batch.snapshot.generation == managementGeneration)
                    let activeTabGeneration = managementGeneration
                    let presentationBeforeUnrelatedRepo = batch.snapshot.results
                    let ownedCapabilityBatchCountBeforeUnrelatedRepo = ownedCapabilityBatchCount()

                    // The dispatcher is process-global, so unrelated toolbar traffic must not be
                    // attributed to this batch owner's exact visible-worktree request set.
                    _ = AppCommandDispatcher.shared.repoExplorerCommandPresentationSnapshot(
                        requests: RepoExplorerToolbarCommandPresentation.requests(
                            nextSortOrder: prefs.sortOrder.toggled
                        ),
                        generation: batch.snapshot.generation &+ 1
                    )

                    _ = store.addRepo(
                        at: FileManager.default.temporaryDirectory.appending(
                            path: "repo-command-batch-\(UUIDv7.generate().uuidString)"
                        )
                    )
                    for _ in 0..<20 { await Task.yield() }
                    #expect(batch.snapshot.generation == activeTabGeneration)
                    #expect(batch.snapshot.results == presentationBeforeUnrelatedRepo)
                    #expect(
                        ownedCapabilityBatchCount() == ownedCapabilityBatchCountBeforeUnrelatedRepo
                    )
                }
            }
        )
    }

    @Test("association move between visible worktrees does not re-resolve")
    func associationMoveBetweenVisibleWorktreesDoesNotReresolve() async throws {
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
                    let batch = RepoExplorerCommandPresentationBatch(
                        store: store,
                        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                        dispatcher: .shared
                    )
                    batch.start()
                    defer { batch.stop() }
                    batch.acceptVisibleWorktreeSnapshot(
                        makeVisibleWorktreeSnapshot(worktreeIDs: Set(worktrees.map(\.id)))
                    )

                    _ = await handler.batchArrivals.wait { _ in true }
                    handler.repoExplorerCapabilityRequestBatches.removeAll()
                    let resultsBeforeMove = batch.snapshot.results

                    // Pane-to-worktree association never changes a capability result: neither
                    // worktree's presentation should re-resolve.
                    _ = store.paneAtom.updatePaneCWDAndResolvedContext(
                        pane.id,
                        cwd: worktrees[1].path,
                        resolvedContext: (repos[1], worktrees[1])
                    )

                    for _ in 0..<1000 { await Task.yield() }

                    #expect(handler.repoExplorerCapabilityRequestBatches.isEmpty)
                    #expect(batch.snapshot.results == resultsBeforeMove)
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
                dispatcher: .shared
            )
            batch.start()
            defer { batch.stop() }
            batch.acceptVisibleWorktreeSnapshot(
                makeVisibleWorktreeSnapshot(worktreeIDs: [])
            )

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

private func makeVisibleWorktreeSnapshot(
    hostLifetimeID: RepoExplorerMaterializationHostLifetimeID = RepoExplorerMaterializationHostLifetimeID(
        rawValue: UUIDv7.generate()
    ),
    worktreeIDs: Set<UUID>,
    repositoryIDs: Set<UUID> = [],
    materializationGeneration: UInt64 = 1,
    visibleRevision: UInt64 = 1
) -> RepoExplorerVisibleWorktreeSnapshot {
    RepoExplorerVisibleWorktreeSnapshot(
        target: RepoExplorerCommandPresentationTarget(
            materializationHostLifetimeID: hostLifetimeID,
            materializationGeneration: materializationGeneration,
            visibleRevision: visibleRevision
        ),
        worktreeIDs: worktreeIDs,
        repositoryIDs: repositoryIDs
    )
}

@MainActor
private final class RepoExplorerCommandPresentationRecordingHandler: WorkspaceCommandHandling {
    let batchArrivals = ExactEventAcknowledgement<Set<RepoExplorerCommandPresentationRequest>>()
    var repoExplorerCapabilityRequestBatches: [Set<RepoExplorerCommandPresentationRequest>] = []
    var capabilityResult = true

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
        return Dictionary(uniqueKeysWithValues: requests.map { ($0, capabilityResult) })
    }
}
