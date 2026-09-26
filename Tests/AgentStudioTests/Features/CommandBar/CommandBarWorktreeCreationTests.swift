import AgentStudioCore
import AgentStudioGit
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite("Command Bar worktree creation", .serialized)
struct CommandBarWorktreeCreationTests {
    private let recentsDefaultsFixture = CommandBarRecentsDefaultsFixture()

    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("New Worktree is the one root command and targets repositories")
    func rootCommandChoosesRepository() throws {
        let fixture = Self.makeFixture()
        let items = CommandBarDataSource.items(
            scope: .commands,
            store: fixture.store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )
        let root = try #require(items.first { $0.id == "cmd-newWorktree" })
        #expect(!items.contains { $0.id == "cmd-forkWorktree" })
        #expect(root.title == AppCommand.newWorktree.definition.label)
        guard case .navigate(let repoLevel) = root.action else {
            Issue.record("Expected repository level")
            return
        }
        #expect(repoLevel.items.map(\.title) == [fixture.repository.name])
        #expect(repoLevel.items.first?.id == "target-newWorktree-repo-\(fixture.repository.id.uuidString)")
    }

    @Test("repo submenu shows resolved default ref and no-default disabling")
    func repoMenuDefaultRef() throws {
        let fixture = Self.makeFixture()
        let pending = CommandBarDataSource.worktreeCreationMenuLevel(repository: fixture.repository)
        let resolved = CommandBarDataSource.worktreeCreationMenuLevel(
            repository: fixture.repository,
            defaultStartPoint: .resolved(displayRef: "origin/main", startPoint: "refs/remotes/origin/main")
        )
        let absent = CommandBarDataSource.worktreeCreationMenuLevel(
            repository: fixture.repository,
            defaultStartPoint: .noDefaultBranch
        )
        #expect(pending.items.map(\.title) == ["From Default", "Fork…"])
        #expect(pending.items[0].isEnabled == false)
        #expect(resolved.items[0].subtitle == "origin/main")
        #expect(resolved.items[0].isEnabled)
        #expect(absent.items[0].subtitle == "no default branch")
        #expect(!absent.items[0].isEnabled)
    }

    @Test("repo menu puts New Worktree first in its Worktrees section")
    func repoMenuCreationRow() {
        let fixture = Self.makeFixture()
        let level = CommandBarDataSource.buildRepoLevel(
            repo: fixture.repository,
            store: fixture.store,
            dispatcher: FakeAppCommandDispatcher()
        )
        let worktreeRows = level.items.filter { $0.group == "Worktrees" }
        #expect(worktreeRows.first?.id == "repo-newWorktree-\(fixture.repository.id.uuidString)")
        #expect(worktreeRows.first?.hasChildren == true)
    }

    @Test("fork picker dims an ineligible worktree and gives its reason")
    func forkPickerEligibility() throws {
        let fixture = Self.makeFixture()
        let unavailable = CommandBarDataSource.worktreeCreationForkPickerLevel(
            repository: fixture.repository,
            eligibilityByWorktreeId: [fixture.worktree.id: .unavailable(reason: "the volume cannot clone files")]
        )
        let available = CommandBarDataSource.worktreeCreationForkPickerLevel(
            repository: fixture.repository,
            eligibilityByWorktreeId: [fixture.worktree.id: .available]
        )
        #expect(unavailable.items.first?.subtitle == "the volume cannot clone files")
        #expect(unavailable.items.first?.isEnabled == false)
        #expect(available.items.first?.isEnabled == true)
    }

    @Test("branch entry creates one row for its selected operation")
    func branchEntryDispatchesSelectedOperation() throws {
        let fixture = Self.makeFixture()
        let fromDefault = CommandBarDataSource.worktreeCreationBranchLevel(
            repository: fixture.repository,
            kind: .fromDefault,
            source: nil,
            sourceDisplay: "origin/main"
        )
        let fork = CommandBarDataSource.worktreeCreationBranchLevel(
            repository: fixture.repository,
            kind: .fork,
            source: fixture.worktree,
            sourceDisplay: fixture.worktree.name
        )
        let input = CommandBarTextEntryInput(text: "feat/new-tree")
        let defaultRow = try #require(fromDefault.textEntry?.rowsForInput(input).first)
        let forkRow = try #require(fork.textEntry?.rowsForInput(input).first)
        #expect(defaultRow.secondaryLine?.text == "→ repo.feat-new-tree")
        #expect(defaultRow.subtitle == "from origin/main")
        #expect(forkRow.subtitle == "from \(fixture.worktree.name)")
        guard case .createWorktree(let defaultDraft) = defaultRow.action,
            case .createWorktree(let forkDraft) = forkRow.action
        else {
            Issue.record("Expected typed creation rows")
            return
        }
        let name = try WorktreeBranchName.validated("feat/new-tree").get()
        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: defaultDraft)
                == .dispatch(.init(kind: .fromDefault, targetId: fixture.repository.id, branchName: name)))
        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: forkDraft)
                == .dispatch(.init(kind: .fork, targetId: fixture.worktree.id, branchName: name)))
        #expect(CommandBarWorktreeCreationResolver.footerHints(for: forkDraft).map(\.id) == ["create-worktree"])
    }

    @Test("worktree menu offers Fork This Worktree")
    func worktreeMenuForkRow() throws {
        let fixture = Self.makeFixture()
        let level = CommandBarDataSource.buildWorktreeActionsLevel(
            worktree: fixture.worktree,
            presence: CommandBarDataSource.emptyWorktreePresence(worktree: fixture.worktree, repo: fixture.repository),
            canOpenInCurrentTab: false,
            dispatcher: FakeAppCommandDispatcher(),
            repository: fixture.repository,
            forkEligibility: .available
        )
        let row = try #require(level.items.first { $0.id == "wt-fork-\(fixture.worktree.id.uuidString)" })
        #expect(row.title == "Fork This Worktree")
        #expect(row.isEnabled)
        #expect(row.hasChildren)
        let unavailableLevel = CommandBarDataSource.buildWorktreeActionsLevel(
            worktree: fixture.worktree,
            presence: CommandBarDataSource.emptyWorktreePresence(worktree: fixture.worktree, repo: fixture.repository),
            canOpenInCurrentTab: false,
            dispatcher: FakeAppCommandDispatcher(),
            repository: fixture.repository,
            forkEligibility: .unavailable(reason: "the volume cannot clone files")
        )
        let unavailableRow = try #require(unavailableLevel.items.first { $0.id == row.id })
        #expect(!unavailableRow.isEnabled)
        #expect(unavailableRow.subtitle == "the volume cannot clone files")
    }

    @Test("controller navigation reaches the repository submenu")
    func controllerOpensRepoMenu() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = CommandBarPanelController(
            store: fixture.store,
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher,
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            recentsDefaults: recentsDefaultsFixture.makeDefaults()
        )
        controller.state.show(prefix: ">")
        let root = try #require(
            CommandBarDataSource.items(
                scope: .commands,
                store: fixture.store,
                repoCache: RepoCacheAtom(),
                dispatcher: dispatcher
            ).first { $0.id == "cmd-newWorktree" })
        controller.executeItem(root)
        let repoRow = try #require(controller.state.currentLevel?.items.first)
        controller.executeItem(repoRow)
        #expect(controller.state.currentLevel?.id == "level-newWorktree-menu-\(fixture.repository.id.uuidString)")
    }

    @Test("Everything breadcrumb uses a house icon with Home accessibility text")
    func everythingBreadcrumbUsesHouse() {
        let state = CommandBarState(defaults: recentsDefaultsFixture.makeDefaults())
        state.show(defaultScope: .everything)
        state.pushLevel(CommandBarLevel(id: "repository", title: "Repository", items: []))
        #expect(state.breadcrumbItems.first?.icon == .home)
        #expect(state.breadcrumbItems.first?.label.isEmpty == true)
        #expect(state.breadcrumbItems.first?.accessibilityLabel == "Home")
    }

    @Test("an old default-branch answer cannot replace the reopened session's answer")
    func staleDefaultQueryIsIgnored() async throws {
        let fixture = Self.makeFixture()
        let resolver = SequencedDefaultStartPointResolver()
        let controller = CommandBarPanelController(
            store: fixture.store,
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher(),
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            recentsDefaults: recentsDefaultsFixture.makeDefaults(),
            defaultStartPointResolver: resolver
        )
        func openMenu() throws {
            controller.state.show(prefix: ">")
            controller.state.pushLevel(
                CommandBarDataSource.buildWorktreeCreationRepoLevel(
                    for: AppCommand.newWorktree.definition,
                    store: fixture.store
                ))
            controller.executeItem(try #require(controller.state.currentLevel?.items.first))
        }

        try openMenu()
        #expect(await resolver.awaitQueries(count: 1) == 1)
        let firstTask = try #require(controller.defaultStartPointQueriesByRepositoryId[fixture.repository.id]?.task)
        controller.state.dismiss()
        try openMenu()
        #expect(await resolver.awaitQueries(count: 2) == 2)
        let secondTask = try #require(controller.defaultStartPointQueriesByRepositoryId[fixture.repository.id]?.task)

        await resolver.answer(at: 0, with: .resolved(displayRef: "origin/old", startPoint: "refs/remotes/origin/old"))
        await firstTask.value
        #expect(controller.state.defaultStartPointByRepositoryId[fixture.repository.id] == nil)
        await resolver.answer(at: 1, with: .resolved(displayRef: "origin/main", startPoint: "refs/remotes/origin/main"))
        await secondTask.value
        #expect(controller.state.currentLevel?.items.first?.subtitle == "origin/main")
    }

    @Test("default answer updates its menu beneath the fork picker")
    func defaultAnswerUpdatesCoveredMenu() async throws {
        let fixture = Self.makeFixture()
        let resolver = SequencedDefaultStartPointResolver()
        let controller = makeController(store: fixture.store, defaultResolver: resolver)
        controller.state.show(prefix: ">")
        controller.state.pushLevel(CommandBarDataSource.worktreeCreationMenuLevel(repository: fixture.repository))
        controller.requestCreationQueriesIfNeeded(for: try #require(controller.state.currentLevel))
        #expect(await resolver.awaitQueries(count: 1) == 1)
        let task = try #require(controller.defaultStartPointQueriesByRepositoryId[fixture.repository.id]?.task)
        controller.executeItem(try #require(controller.state.currentLevel?.items.last))
        await resolver.answer(at: 0, with: .resolved(displayRef: "origin/main", startPoint: "refs/remotes/origin/main"))
        await task.value
        controller.state.popLevel()
        #expect(controller.state.currentLevel?.items.first?.subtitle == "origin/main")
    }

    @Test("a pending default answer cannot restore creation rows after the repository becomes unavailable")
    func unavailableRepositoryCannotReviveCreationRows() async throws {
        let fixture = Self.makeFixture()
        let resolver = SequencedDefaultStartPointResolver()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = makeController(store: fixture.store, dispatcher: dispatcher, defaultResolver: resolver)
        controller.state.show(prefix: ">")
        controller.state.pushLevel(CommandBarDataSource.worktreeCreationMenuLevel(repository: fixture.repository))
        controller.requestCreationQueriesIfNeeded(for: try #require(controller.state.currentLevel))
        #expect(await resolver.awaitQueries(count: 1) == 1)
        let task = try #require(controller.defaultStartPointQueriesByRepositoryId[fixture.repository.id]?.task)
        fixture.store.markRepoUnavailable(fixture.repository.id)

        await resolver.answer(at: 0, with: .resolved(displayRef: "origin/main", startPoint: "refs/remotes/origin/main"))
        await task.value

        #expect(controller.state.currentLevel?.items.isEmpty == true)
        let currentSnapshot = snapshot(for: controller, store: fixture.store, dispatcher: dispatcher)
        #expect(currentSnapshot.displayedItems.isEmpty)
        #expect(currentSnapshot.selectedItem == nil)
        #expect(dispatcher.worktreeCreationDispatches.isEmpty)
    }

    @Test("fork answer updates its picker beneath a child level")
    func forkAnswerUpdatesCoveredPicker() async throws {
        let fixture = Self.makeFixture()
        let checker = SequencedForkEligibilityChecker()
        let controller = makeController(store: fixture.store, forkChecker: checker)
        controller.state.show(prefix: ">")
        controller.state.pushLevel(CommandBarDataSource.worktreeCreationForkPickerLevel(repository: fixture.repository))
        controller.requestCreationQueriesIfNeeded(for: try #require(controller.state.currentLevel))
        #expect(await checker.awaitQueries(count: 1) == 1)
        let task = try #require(controller.forkEligibilityQueriesBySourceWorktreeId[fixture.worktree.id]?.task)
        controller.state.pushLevel(CommandBarLevel(id: "child", title: "Child", items: []))
        await checker.answer(at: 0, with: .available)
        await task.value
        controller.state.popLevel()
        #expect(controller.state.currentLevel?.items.first?.isEnabled == true)
        #expect(controller.state.currentLevel?.items.first?.subtitle == fixture.repository.name)
    }

    @Test("worktree-menu answer updates its row beneath a child level")
    func worktreeAnswerUpdatesCoveredMenu() async throws {
        let fixture = Self.makeFixture()
        let checker = SequencedForkEligibilityChecker()
        let controller = makeController(store: fixture.store, forkChecker: checker)
        controller.state.show(prefix: "#")
        controller.state.pushLevel(
            CommandBarDataSource.buildWorktreeActionsLevel(
                worktree: fixture.worktree,
                presence: CommandBarDataSource.buildWorktreePresence(
                    worktree: fixture.worktree, repo: fixture.repository, store: fixture.store),
                canOpenInCurrentTab: false,
                dispatcher: FakeAppCommandDispatcher(),
                repository: fixture.repository
            ))
        controller.requestCreationQueriesIfNeeded(for: try #require(controller.state.currentLevel))
        #expect(await checker.awaitQueries(count: 1) == 1)
        let task = try #require(controller.forkEligibilityQueriesBySourceWorktreeId[fixture.worktree.id]?.task)
        controller.state.pushLevel(CommandBarLevel(id: "child", title: "Child", items: []))
        await checker.answer(at: 0, with: .unavailable(reason: "the volume cannot clone files"))
        await task.value
        controller.state.popLevel()
        let row = try #require(
            controller.state.currentLevel?.items.first {
                $0.id == "wt-fork-\(fixture.worktree.id.uuidString)"
            })
        #expect(row.subtitle == "the volume cannot clone files")
        #expect(!row.isEnabled)
    }

    @Test("old fork answer is ignored after reopening")
    func staleForkAnswerIsIgnored() async throws {
        let fixture = Self.makeFixture()
        let checker = SequencedForkEligibilityChecker()
        let controller = makeController(store: fixture.store, forkChecker: checker)
        func openPicker() throws {
            controller.state.show(prefix: ">")
            controller.state.pushLevel(
                CommandBarDataSource.worktreeCreationForkPickerLevel(repository: fixture.repository))
            controller.requestCreationQueriesIfNeeded(for: try #require(controller.state.currentLevel))
        }
        try openPicker()
        #expect(await checker.awaitQueries(count: 1) == 1)
        let firstTask = try #require(controller.forkEligibilityQueriesBySourceWorktreeId[fixture.worktree.id]?.task)
        controller.state.dismiss()
        try openPicker()
        #expect(await checker.awaitQueries(count: 2) == 2)
        let secondTask = try #require(controller.forkEligibilityQueriesBySourceWorktreeId[fixture.worktree.id]?.task)
        await checker.answer(at: 0, with: .available)
        await firstTask.value
        #expect(controller.state.forkEligibilityBySourceWorktreeId[fixture.worktree.id] == nil)
        await checker.answer(at: 1, with: .unavailable(reason: "unavailable now"))
        await secondTask.value
        #expect(controller.state.currentLevel?.items.first?.subtitle == "unavailable now")
    }

    @Test("invalid or refused creation rows are dimmed and do not dispatch")
    func invalidAndRefusedCreationRowsDoNotDispatch() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = makeController(store: fixture.store, dispatcher: dispatcher)
        controller.state.show(prefix: ">")
        controller.state.pushLevel(
            CommandBarDataSource.worktreeCreationBranchLevel(
                repository: fixture.repository, kind: .fromDefault, source: nil, sourceDisplay: "main"))
        controller.state.rawInput = "bad name"
        let invalid = try #require(
            snapshot(for: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)
        #expect(
            snapshot(for: controller, store: fixture.store, dispatcher: dispatcher).dimmedItemIds.contains(invalid.id))
        controller.executeItem(invalid)
        #expect(dispatcher.worktreeCreationDispatches.isEmpty)

        controller.state.rawInput = "feat/valid"
        dispatcher.availableCommands.remove(.newWorktreeFromDefault)
        let refused = try #require(
            snapshot(for: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)
        #expect(
            snapshot(for: controller, store: fixture.store, dispatcher: dispatcher).dimmedItemIds.contains(refused.id))
        controller.executeItem(refused)
        #expect(dispatcher.worktreeCreationDispatches.isEmpty)
    }

    @Test("dimmed eligibility and no-default rows cannot be executed")
    func dimmedNavigationRowsDoNotDispatch() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = makeController(store: fixture.store, dispatcher: dispatcher)
        controller.state.show(prefix: ">")
        controller.state.pushLevel(
            CommandBarDataSource.worktreeCreationMenuLevel(
                repository: fixture.repository, defaultStartPoint: .noDefaultBranch))
        let noDefault = try #require(controller.state.currentLevel?.items.first)
        #expect(
            snapshot(for: controller, store: fixture.store, dispatcher: dispatcher).dimmedItemIds.contains(noDefault.id)
        )
        controller.executeItem(noDefault)
        #expect(controller.state.currentLevel?.id == "level-newWorktree-menu-\(fixture.repository.id.uuidString)")
        controller.state.pushLevel(
            CommandBarDataSource.worktreeCreationForkPickerLevel(
                repository: fixture.repository,
                eligibilityByWorktreeId: [fixture.worktree.id: .unavailable(reason: "unavailable")]
            ))
        let ineligible = try #require(controller.state.currentLevel?.items.first)
        #expect(
            snapshot(for: controller, store: fixture.store, dispatcher: dispatcher).dimmedItemIds.contains(
                ineligible.id))
        controller.executeItem(ineligible)
        #expect(controller.state.currentLevel?.id == "level-newWorktree-fork-\(fixture.repository.id.uuidString)")
        #expect(dispatcher.worktreeCreationDispatches.isEmpty)
    }

    @Test("Create dispatches typed repository and worktree targets")
    func createDispatchesBothTargets() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = makeController(store: fixture.store, dispatcher: dispatcher)
        controller.state.show(prefix: ">")
        for (kind, source, targetId, targetType) in [
            (WorktreeCreationKind.fromDefault, Optional<Worktree>.none, fixture.repository.id, SearchItemType.repo),
            (.fork, Optional(fixture.worktree), fixture.worktree.id, .worktree),
        ] {
            controller.state.pushLevel(
                CommandBarDataSource.worktreeCreationBranchLevel(
                    repository: fixture.repository, kind: kind, source: source, sourceDisplay: "main"))
            controller.state.rawInput = "feat/created"
            let row = try #require(
                snapshot(for: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)
            controller.executeItem(row)
            let request = try #require(dispatcher.worktreeCreationDispatches.last)
            #expect(request.kind == kind)
            #expect(request.targetId == targetId)
            #expect(request.targetType == targetType)
            controller.state.show(prefix: ">")
        }
        #expect(dispatcher.worktreeCreationDispatches.count == 2)
    }

    private func makeController(
        store: WorkspaceStore,
        dispatcher: FakeAppCommandDispatcher = FakeAppCommandDispatcher(),
        forkChecker: (any WorktreeForkEligibilityChecking)? = nil,
        defaultResolver: (any WorktreeDefaultStartPointResolving)? = nil
    ) -> CommandBarPanelController {
        CommandBarPanelController(
            store: store,
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher,
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            recentsDefaults: recentsDefaultsFixture.makeDefaults(),
            worktreeForkEligibility: forkChecker,
            defaultStartPointResolver: defaultResolver
        )
    }

    private func snapshot(
        for controller: CommandBarPanelController,
        store: WorkspaceStore,
        dispatcher: FakeAppCommandDispatcher
    ) -> CommandBarResultSnapshot {
        CommandBarResultSession(store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
            .snapshot(state: controller.state)
    }

    private static func makeFixture() -> (store: WorkspaceStore, repository: Repo, worktree: Worktree) {
        let store = WorkspaceStore()
        let path = URL(filePath: "/tmp/command-bar-worktree-creation-\(UUIDv7.generate().uuidString)/repo")
        let repository = store.addRepo(at: path)
        let worktree = Worktree(repoId: repository.id, name: "main", path: path, isMainWorktree: true)
        store.reconcileDiscoveredWorktrees(repository.id, worktrees: [worktree])
        guard let resolved = store.repositoryTopologyAtom.repo(repository.id),
            let source = resolved.worktrees.first
        else { preconditionFailure("Expected repository and worktree") }
        return (store, resolved, source)
    }
}

private actor SequencedDefaultStartPointResolver: WorktreeDefaultStartPointResolving {
    private var queryCount = 0
    private var pending: [Int: CheckedContinuation<WorktreeDefaultStartPoint, Never>] = [:]
    private var arrivalWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func resolveDefaultStartPoint(repositoryPath _: URL) async throws(GitDataPlaneError) -> WorktreeDefaultStartPoint {
        let index = queryCount
        queryCount += 1
        let ready = arrivalWaiters.filter { $0.0 <= queryCount }
        arrivalWaiters.removeAll { $0.0 <= queryCount }
        for (_, continuation) in ready { continuation.resume() }
        return await withCheckedContinuation { pending[index] = $0 }
    }

    func awaitQueries(count: Int) async -> Int {
        if queryCount < count {
            await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
        }
        return queryCount
    }

    func answer(at index: Int, with resolution: WorktreeDefaultStartPoint) {
        pending.removeValue(forKey: index)?.resume(returning: resolution)
    }
}

private actor SequencedForkEligibilityChecker: WorktreeForkEligibilityChecking {
    private var queryCount = 0
    private var pending: [Int: CheckedContinuation<WorktreeForkEligibility, Never>] = [:]
    private var arrivalWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func forkEligibility(sourceWorktreePath _: URL, destinationDirectory _: URL) async -> WorktreeForkEligibility {
        let index = queryCount
        queryCount += 1
        let ready = arrivalWaiters.filter { $0.0 <= queryCount }
        arrivalWaiters.removeAll { $0.0 <= queryCount }
        for (_, continuation) in ready { continuation.resume() }
        return await withCheckedContinuation { pending[index] = $0 }
    }

    func awaitQueries(count: Int) async -> Int {
        if queryCount < count {
            await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
        }
        return queryCount
    }

    func answer(at index: Int, with eligibility: WorktreeForkEligibility) {
        pending.removeValue(forKey: index)?.resume(returning: eligibility)
    }
}
