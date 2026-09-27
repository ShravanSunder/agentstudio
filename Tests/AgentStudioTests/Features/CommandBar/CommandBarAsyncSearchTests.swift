import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import AgentStudioCommandBar

private actor ControlledCommandBarSearchService: SearchServicing {
    private var installedSets: [SearchDocumentSet] = []
    private var installWaiters: [CheckedContinuation<SearchDocumentSet, Never>] = []
    private var admittedRequests: [SearchRequest] = []
    private var requestWaiters: [CheckedContinuation<SearchRequest, Never>] = []
    private var answerWaiters: [UInt64: CheckedContinuation<SearchResultSet, Never>] = [:]

    func search(_ request: SearchRequest) async -> SearchResultSet {
        if requestWaiters.isEmpty {
            admittedRequests.append(request)
        } else {
            requestWaiters.removeFirst().resume(returning: request)
        }
        return await withCheckedContinuation { continuation in
            answerWaiters[request.sequence.value] = continuation
        }
    }

    func install(_ documentSet: SearchDocumentSet) async {
        if installWaiters.isEmpty {
            installedSets.append(documentSet)
        } else {
            installWaiters.removeFirst().resume(returning: documentSet)
        }
    }

    func nextInstall() async -> SearchDocumentSet {
        if !installedSets.isEmpty { return installedSets.removeFirst() }
        return await withCheckedContinuation { installWaiters.append($0) }
    }

    func requestCount() -> Int { admittedRequests.count }

    func nextRequest() async -> SearchRequest {
        if !admittedRequests.isEmpty { return admittedRequests.removeFirst() }
        return await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func release(_ result: SearchResultSet) {
        answerWaiters.removeValue(forKey: result.sequence.value)?.resume(returning: result)
    }
}

@MainActor
@Suite(.serialized)
struct CommandBarAsyncSearchTests {
    private let recentsDefaultsFixture = CommandBarRecentsDefaultsFixture()

    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("open and topology invalidation install their generations before a query")
    func generationInstalledAheadOfQuery() async {
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service)
        controller.state.show(prefix: ">")
        controller.queryChanged(text: controller.state.rawInput)
        let openSet = await service.nextInstall()
        #expect(await service.requestCount() == 0)

        controller.searchContextChanged()
        let changedSet = await service.nextInstall()
        #expect(changedSet.generation > openSet.generation)
        #expect(await service.requestCount() == 0)
    }

    @Test("a late first answer cannot replace the newest applied query")
    func lateAnswerIsDropped() async throws {
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service)
        controller.state.show(prefix: ">")

        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        let firstRequest = await service.nextRequest()
        let firstTask = try #require(controller.pendingSearchTask)

        controller.state.rawInput = "> close tab"
        controller.queryChanged(text: controller.state.rawInput)
        let latestRequest = await service.nextRequest()
        let latestTask = try #require(controller.pendingSearchTask)

        await service.release(answer(for: latestRequest))
        await latestTask.value
        #expect(controller.state.appliedSearchResult?.sequence == latestRequest.sequence)

        await service.release(answer(for: firstRequest))
        await firstTask.value
        #expect(controller.state.appliedSearchResult?.sequence == latestRequest.sequence)
    }

    @Test("clearing or switching scope invalidates a pending answer")
    func clearAndScopeSwitchInvalidateAnswers() async throws {
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service)
        controller.state.show(prefix: ">")

        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        let clearingRequest = await service.nextRequest()
        let clearingTask = try #require(controller.pendingSearchTask)
        controller.state.rawInput = "> "
        controller.queryChanged(text: controller.state.rawInput)
        await service.release(answer(for: clearingRequest))
        await clearingTask.value
        #expect(controller.state.appliedSearchResult == nil)

        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        let scopeRequest = await service.nextRequest()
        let scopeTask = try #require(controller.pendingSearchTask)
        controller.state.switchPrefix("#")
        controller.searchContextChanged()
        await service.release(answer(for: scopeRequest))
        await scopeTask.value
        #expect(controller.state.appliedSearchResult == nil)
    }

    @Test("an accepted empty answer clamps selection after a prior result")
    func acceptedEmptyAnswerClampsSelection() async throws {
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service)
        controller.state.show(prefix: ">")
        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        let firstRequest = await service.nextRequest()
        let firstTask = try #require(controller.pendingSearchTask)
        await service.release(answer(for: firstRequest))
        await firstTask.value
        #expect(controller.state.appliedSearchResult?.displayedItems.isEmpty == false)

        controller.state.selectedIndex = 1000
        controller.state.rawInput = "> no command can match this sentinel"
        controller.queryChanged(text: controller.state.rawInput)
        let emptyRequest = await service.nextRequest()
        let emptyTask = try #require(controller.pendingSearchTask)
        await service.release(answer(for: emptyRequest, ids: []))
        await emptyTask.value
        #expect(controller.state.appliedSearchResult?.displayedItems.isEmpty == true)
        #expect(controller.state.selectedIndex == 0)
    }

    @Test("dismiss and reopen reject an answer from the prior bar session")
    func dismissReopenInvalidatesOldAnswer() async throws {
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service)
        controller.state.show(prefix: ">")
        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        let oldRequest = await service.nextRequest()
        let oldTask = try #require(controller.pendingSearchTask)

        controller.dismiss()
        controller.state.show(prefix: ">")
        controller.state.rawInput = "> new"
        controller.searchContextChanged()
        let newRequest = await service.nextRequest()
        let newTask = try #require(controller.pendingSearchTask)
        await service.release(answer(for: newRequest))
        await newTask.value
        #expect(controller.state.appliedSearchResult?.sequence == newRequest.sequence)

        await service.release(answer(for: oldRequest))
        await oldTask.value
        #expect(controller.state.appliedSearchResult?.sequence == newRequest.sequence)
    }

    @Test("level push and pop invalidate the pending root answer")
    func pushAndPopInvalidateOldAnswer() async throws {
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service)
        controller.state.show(prefix: ">")
        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        let oldRequest = await service.nextRequest()
        let oldTask = try #require(controller.pendingSearchTask)

        controller.state.pushLevel(
            CommandBarLevel(id: "actions", title: "Actions", items: [])
        )
        controller.searchContextChanged()
        controller.state.popLevel()
        controller.searchContextChanged()
        await service.release(answer(for: oldRequest))
        await oldTask.value
        #expect(controller.state.appliedSearchResult == nil)

        controller.state.rawInput = "> new"
        controller.queryChanged(text: controller.state.rawInput)
        let newRequest = await service.nextRequest()
        let newTask = try #require(controller.pendingSearchTask)
        await service.release(answer(for: newRequest))
        await newTask.value
        #expect(controller.state.appliedSearchResult?.sequence == newRequest.sequence)
    }

    @Test("in-place level replacement uses ranges from the new title")
    func replacedLevelRejectsOldTitleRange() async throws {
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service)
        controller.state.show(prefix: ">")
        controller.state.pushLevel(
            CommandBarLevel(
                id: "rename-level",
                title: "Actions",
                items: [
                    CommandBarItem(
                        id: "renamed", title: "oauth-long", group: "Actions", groupPriority: 1, action: .custom({}))
                ]
            )
        )
        controller.state.rawInput = "oauth"
        controller.searchContextChanged()
        let oldRequest = await service.nextRequest()
        let oldTask = try #require(controller.pendingSearchTask)

        controller.state.replaceLevel(
            CommandBarLevel(
                id: "rename-level",
                title: "Actions",
                items: [
                    CommandBarItem(
                        id: "renamed", title: "oauth", group: "Actions", groupPriority: 1, action: .custom({}))
                ]
            )
        )
        controller.searchContextChanged()
        let newRequest = await service.nextRequest()
        let newTask = try #require(controller.pendingSearchTask)
        #expect(newRequest.documentSet.generation > oldRequest.documentSet.generation)

        await service.release(answer(for: oldRequest, ids: ["renamed"], titleMatch: 0..<10))
        await oldTask.value
        #expect(controller.state.appliedSearchResult == nil)
        await service.release(answer(for: newRequest, ids: ["renamed"], titleMatch: 0..<5))
        await newTask.value
        #expect(controller.state.appliedSearchResult?.displayedItems.first?.title == "oauth")
        #expect(controller.state.appliedSearchResult?.titleMatchesByItemId["renamed"] == 0..<5)
    }

    @Test("nested worktree row is withdrawn before answer application")
    func withdrawnNestedWorktreeIsDropped() async throws {
        let store = WorkspaceStore()
        let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-withdrawn-nested"))
        let worktree = try #require(repository.worktrees.first)
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service, store: store)
        controller.state.show(prefix: "#")
        controller.state.pushLevel(
            CommandBarLevel(
                id: "worktree-targets",
                title: "Targets",
                items: [
                    CommandBarItem(
                        id: "nested-worktree",
                        title: "oauth target",
                        group: "Worktrees",
                        groupPriority: 1,
                        action: .dispatchTargeted(.openWorktree, target: worktree.id, targetType: .worktree)
                    )
                ]
            )
        )
        controller.state.rawInput = "oauth"
        controller.searchContextChanged()
        let request = await service.nextRequest()
        let task = try #require(controller.pendingSearchTask)

        store.mutationCoordinator.markRepoUnavailable(repository.id)
        await service.release(answer(for: request, ids: ["nested-worktree"]))
        await task.value
        #expect(controller.state.appliedSearchResult?.displayedItems.isEmpty == true)
    }

    @Test("root repository withdrawal is absent from the next applied answer")
    func withdrawnRootRepositoryIsDropped() async throws {
        let store = WorkspaceStore()
        let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-withdrawn-root"))
        let service = ControlledCommandBarSearchService()
        let controller = makeController(service: service, store: store)
        controller.state.show(prefix: "#")
        controller.state.rawInput = "# withdrawn"
        controller.queryChanged(text: controller.state.rawInput)
        let oldRequest = await service.nextRequest()
        let oldTask = try #require(controller.pendingSearchTask)
        let repositoryId = "repo-\(repository.id.uuidString)"

        store.mutationCoordinator.markRepoUnavailable(repository.id)
        await service.release(answer(for: oldRequest, ids: [repositoryId]))
        await oldTask.value
        if controller.searchSequence > oldRequest.sequence.value {
            let refreshedRequest = await service.nextRequest()
            let refreshedTask = try #require(controller.pendingSearchTask)
            await service.release(answer(for: refreshedRequest, ids: [repositoryId]))
            await refreshedTask.value
        }
        #expect(controller.state.appliedSearchResult?.displayedItems.contains { $0.id == repositoryId } != true)
    }

    @Test("a changed row generation resubmits the current text once")
    func staleGenerationResubmits() async throws {
        let service = ControlledCommandBarSearchService()
        let store = WorkspaceStore()
        let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-generation"))
        let controller = makeController(service: service, store: store)
        controller.state.show(prefix: "#")
        controller.state.rawInput = "# command"
        controller.queryChanged(text: controller.state.rawInput)
        let oldRequest = await service.nextRequest()
        let oldTask = try #require(controller.pendingSearchTask)

        try store.mutationCoordinator.setRepoTags(["generation-two"], repositoryID: repository.id)

        await service.release(answer(for: oldRequest))
        await oldTask.value
        #expect(controller.state.appliedSearchResult == nil)

        let newRequest = await service.nextRequest()
        let newTask = try #require(controller.pendingSearchTask)
        #expect(newRequest.documentSet.generation > oldRequest.documentSet.generation)
        let repositoryId = "repo-\(repository.id.uuidString)"
        await service.release(answer(for: newRequest, ids: [repositoryId]))
        await newTask.value
        #expect(controller.state.appliedSearchResult?.generation == newRequest.documentSet.generation)
        #expect(controller.state.appliedSearchResult?.displayedItems.map(\.id) == [repositoryId])
    }

    @Test("real service carries root, repository and nested rows through apply")
    func realServiceIntegrationAcrossScopes() async throws {
        let store = WorkspaceStore()
        let repository = store.addRepo(at: URL(filePath: "/tmp/search-repository"))
        let worktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repository.id,
            name: "oauth-work",
            path: URL(filePath: "/tmp/checkout-folder")
        )
        store.reconcileDiscoveredWorktrees(repository.id, worktrees: repository.worktrees + [worktree])
        let repoCache = RepoCacheAtom()
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repository.id, branch: "feature/token-refresh")
        )
        let controller = makeController(service: SearchService(), store: store, repoCache: repoCache)
        let worktreeId = "repo-wt-\(worktree.id.uuidString)"

        controller.state.show(defaultScope: .everything)
        controller.state.rawInput = "oauth"
        controller.queryChanged(text: controller.state.rawInput)
        await controller.pendingSearchTask?.value
        #expect(controller.state.appliedSearchResult?.groups.map(\.id).contains("Worktrees") == true)
        #expect(controller.state.appliedSearchResult?.displayedItems.map(\.id).contains(worktreeId) == true)

        controller.state.switchPrefix("#")
        controller.searchContextChanged()
        controller.state.rawInput = "# token-refresh"
        controller.queryChanged(text: controller.state.rawInput)
        await controller.pendingSearchTask?.value
        #expect(controller.state.appliedSearchResult?.displayedItems.map(\.id).contains(worktreeId) == true)

        let currentRepository = try #require(store.repositoryTopologyAtom.repo(repository.id))
        controller.state.pushLevel(
            CommandBarDataSource.buildRepoLevel(
                repo: currentRepository,
                store: store,
                dispatcher: FakeAppCommandDispatcher()
            )
        )
        controller.state.rawInput = "copy"
        controller.searchContextChanged()
        await controller.pendingSearchTask?.value
        #expect(controller.state.appliedSearchResult?.displayedItems.contains { $0.title.contains("Copy") } == true)
    }

    @Test("the next real query sees a branch change on the same worktree")
    func branchChangeRefreshesSearchGeneration() async {
        let store = WorkspaceStore()
        let repository = store.addRepo(at: URL(filePath: "/tmp/command-bar-branch-refresh"))
        let worktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repository.id,
            name: "checkout",
            path: URL(filePath: "/tmp/command-bar-branch-refresh/checkout")
        )
        store.reconcileDiscoveredWorktrees(repository.id, worktrees: repository.worktrees + [worktree])
        let repoCache = RepoCacheAtom()
        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repository.id, branch: "feature/alpha")
        )
        let controller = makeController(service: SearchService(), store: store, repoCache: repoCache)
        let worktreeId = "repo-wt-\(worktree.id.uuidString)"
        controller.state.show(prefix: "#")
        controller.state.rawInput = "# alpha"
        controller.queryChanged(text: controller.state.rawInput)
        await controller.pendingSearchTask?.value
        let firstGeneration = controller.state.appliedSearchResult?.generation
        #expect(controller.state.appliedSearchResult?.displayedItems.map(\.id).contains(worktreeId) == true)

        repoCache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repository.id, branch: "feature/beta")
        )
        controller.state.rawInput = "# beta"
        controller.queryChanged(text: controller.state.rawInput)
        await controller.pendingSearchTask?.value
        #expect(controller.state.appliedSearchResult?.generation != firstGeneration)
        #expect(controller.state.appliedSearchResult?.displayedItems.map(\.id).contains(worktreeId) == true)

        controller.state.rawInput = "# alpha"
        controller.queryChanged(text: controller.state.rawInput)
        await controller.pendingSearchTask?.value
        #expect(controller.state.appliedSearchResult?.displayedItems.map(\.id).contains(worktreeId) != true)
    }

    @Test("holding publication increases the recorded input-to-publication interval")
    func publicationStageIsCausal() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "command-bar-search-measurement-\(UUIDv7.generate().uuidString)")
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "command-bar-search-measurement",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 731,
            timeUnixNano: { 1 }
        )
        let traceRecorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        let clock = Mutex<UInt64>(1_000_000)
        let service = ControlledCommandBarSearchService()
        let controller = makeController(
            service: service,
            traceRecorder: traceRecorder,
            nowNanoseconds: { clock.withLock { $0 } }
        )
        controller.state.show(prefix: ">")

        controller.state.rawInput = "> close"
        controller.queryChanged(text: controller.state.rawInput)
        let firstRequest = await service.nextRequest()
        let firstTask = try #require(controller.pendingSearchTask)
        clock.withLock { $0 = 2_000_000 }
        await service.release(answer(for: firstRequest))
        await firstTask.value
        clock.withLock { $0 = 3_000_000 }
        controller.acknowledgeResultPublished(
            sequence: firstRequest.sequence,
            generation: firstRequest.documentSet.generation
        )

        clock.withLock { $0 = 4_000_000 }
        controller.state.rawInput = "> new"
        controller.queryChanged(text: controller.state.rawInput)
        let secondRequest = await service.nextRequest()
        let secondTask = try #require(controller.pendingSearchTask)
        clock.withLock { $0 = 5_000_000 }
        await service.release(answer(for: secondRequest))
        await secondTask.value
        clock.withLock { $0 = 10_000_000 }
        controller.acknowledgeResultPublished(
            sequence: secondRequest.sequence,
            generation: secondRequest.documentSet.generation
        )

        try await traceRecorder.drain()
        let outputURL = try #require(traceRuntime.outputFileURL)
        let records = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
        let intervals = records.compactMap { record -> Double? in
            guard let attributes = record["attributes"] as? [String: Any],
                attributes["agentstudio.performance.commandbar.search.stage"] as? String == "end_to_end"
            else { return nil }
            return attributes["agentstudio.performance.elapsed_ms"] as? Double
        }
        #expect(intervals.count == 2)
        if intervals.count == 2 {
            #expect(intervals[1] > intervals[0])
        }
    }

    private func makeController(
        service: any SearchServicing,
        store: WorkspaceStore = WorkspaceStore(),
        repoCache: RepoCacheAtom = RepoCacheAtom(),
        traceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        nowNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) -> CommandBarPanelController {
        CommandBarPanelController(
            store: store,
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: repoCache,
            dispatcher: FakeAppCommandDispatcher(),
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            searchService: service,
            performanceTraceRecorder: traceRecorder,
            searchNowNanoseconds: nowNanoseconds,
            recentsDefaults: recentsDefaultsFixture.makeDefaults()
        )
    }

    private func answer(
        for request: SearchRequest,
        ids: [String]? = nil,
        titleMatch: Range<Int>? = nil
    ) -> SearchResultSet {
        let selectedDocuments = request.documentSet.documents.filter { document in
            ids?.contains(document.itemId.rawValue) ?? document.title.localizedCaseInsensitiveContains(request.text)
        }
        let groupedMatches = Dictionary(grouping: selectedDocuments, by: \.groupId)
        let groups = request.documentSet.groups.compactMap { group -> SearchResultGroup? in
            guard let documents = groupedMatches[group.id], !documents.isEmpty else { return nil }
            return SearchResultGroup(
                groupId: group.id,
                matches: documents.map { SearchMatch(itemId: $0.itemId, titleMatch: titleMatch) }
            )
        }
        return SearchResultSet(
            sequence: request.sequence,
            generation: request.documentSet.generation,
            groups: groups,
            outcome: .answered
        )
    }
}
