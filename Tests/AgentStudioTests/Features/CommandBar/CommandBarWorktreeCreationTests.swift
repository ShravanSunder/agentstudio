import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite("Command Bar worktree creation", .serialized)
struct CommandBarWorktreeCreationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("the commands scope has one worktree-creation root row and no fork root row")
    func commandsScopeHasOneCreationRootRow() {
        let fixture = Self.makeFixture()

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: fixture.store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        let creationRows = items.filter { $0.id == "cmd-newWorktree" || $0.id == "cmd-forkWorktree" }
        #expect(creationRows.map(\.id) == ["cmd-newWorktree"])
        #expect(creationRows.first?.title == AppCommand.newWorktree.definition.label)
        #expect(creationRows.first?.hasChildren == true)
    }

    @Test("choosing a source worktree pushes a branch-name text-entry level")
    func choosingSourcePushesTextEntryLevel() throws {
        let fixture = Self.makeFixture()
        let controller = Self.makeController(store: fixture.store, dispatcher: FakeAppCommandDispatcher())

        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)

        let level = try #require(controller.state.currentLevel)
        #expect(level.textEntry != nil)
        #expect(level.title == fixture.worktree.name)
        #expect(controller.state.placeholder == "Branch name...")
    }

    @Test("typing a valid branch name produces one actionable Create row carrying the fork cue")
    func typingProducesCreateRow() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = Self.makeController(store: fixture.store, dispatcher: dispatcher)
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)

        controller.state.rawInput = "feature/worktree-commands"
        let snapshot = Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher)

        let row = try #require(snapshot.displayedItems.first)
        #expect(snapshot.displayedItems.count == 1)
        #expect(row.title == "feature/worktree-commands")
        #expect(row.secondaryLine?.text == AppCommand.forkWorktree.definition.helpText)
        #expect(!snapshot.dimmedItemIds.contains(row.id))
        #expect(snapshot.footerHints.map(\.id).contains("create-fork"))
        #expect(snapshot.footerHints.map(\.id).contains("create-clean"))
        #expect(snapshot.footerHints.first { $0.id == "create-fork" }?.label == "Fork Worktree")
        #expect(snapshot.footerHints.first { $0.id == "create-clean" }?.label == "New Worktree")
    }

    @Test("an empty or invalid branch name keeps the Create row visible but disabled")
    func invalidBranchNameDisablesRow() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = Self.makeController(store: fixture.store, dispatcher: dispatcher)
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)

        for (text, reason) in [
            ("", "Type a branch name"),
            ("has space", "Branch names cannot contain spaces or control characters"),
            ("feature..x", "Branch names cannot contain \"..\""),
        ] {
            controller.state.rawInput = text
            let snapshot = Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher)
            let row = try #require(snapshot.displayedItems.first)
            #expect(snapshot.dimmedItemIds.contains(row.id), "\(text) should disable the Create row")
            #expect(row.secondaryLine?.text == reason)
        }
    }

    @Test("Back returns from the branch level to the source level with the input cleared")
    func backReturnsToSourceLevel() throws {
        let fixture = Self.makeFixture()
        let controller = Self.makeController(store: fixture.store, dispatcher: FakeAppCommandDispatcher())
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        controller.state.rawInput = "feature/back"

        controller.state.popLevel()

        #expect(controller.state.currentLevel?.id == "level-newWorktree-source")
        #expect(controller.state.rawInput.isEmpty)
    }

    @Test("Return and Command-Return fork; Option-Return creates a clean checkout")
    func resolverMapsModifiersToCommands() throws {
        let sourceId = UUIDv7.generate()
        let branchName = try WorktreeBranchName.validated("feature/resolve").get()
        let draft = CommandBarWorktreeCreationDraft(
            sourceWorktreeId: sourceId, branchName: .success(branchName), forkEligibility: .available)

        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: .plain)
                == .dispatch(.init(kind: .fork, sourceWorktreeId: sourceId, branchName: branchName)))
        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: .command)
                == .dispatch(.init(kind: .fork, sourceWorktreeId: sourceId, branchName: branchName)))
        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: .option)
                == .dispatch(.init(kind: .cleanCheckout, sourceWorktreeId: sourceId, branchName: branchName)))
        let invalidDraft = CommandBarWorktreeCreationDraft(sourceWorktreeId: sourceId, branchName: .failure(.empty))
        #expect(CommandBarWorktreeCreationResolver.resolve(draft: invalidDraft, modifier: .plain) == .notActionable)
    }

    @Test("Option-Return on the Create row dispatches a clean-checkout creation request")
    func optionReturnDispatchesCleanCheckout() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = Self.makeController(store: fixture.store, dispatcher: dispatcher)
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        controller.state.rawInput = "feature/clean"
        let row = try #require(
            Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first
        )

        let expectedBranchName = try WorktreeBranchName.validated("feature/clean").get()

        controller.executeItem(row, modifier: .option)

        #expect(
            dispatcher.worktreeCreationDispatches == [
                WorktreeCreationRequest(
                    kind: .cleanCheckout,
                    sourceWorktreeId: fixture.worktree.id,
                    branchName: expectedBranchName
                )
            ])
    }

    @Test("an unavailable command for the chosen modifier dispatches nothing")
    func unavailableModifierDispatchesNothing() throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        dispatcher.availableCommands.remove(.forkWorktree)
        let controller = Self.makeController(store: fixture.store, dispatcher: dispatcher)
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        controller.state.rawInput = "feature/fork"
        let row = try #require(
            Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first
        )

        controller.executeItem(row, modifier: .plain)

        #expect(dispatcher.worktreeCreationDispatches.isEmpty)
    }

    // MARK: - Fork eligibility

    @Test("where fork is unavailable every Return creates a clean checkout")
    func unavailableForkResolvesEveryReturnToCleanCheckout() throws {
        let sourceId = UUIDv7.generate()
        let branchName = try WorktreeBranchName.validated("feature/fallback").get()
        let draft = CommandBarWorktreeCreationDraft(
            sourceWorktreeId: sourceId,
            branchName: .success(branchName),
            forkEligibility: .unavailable(reason: "the volume cannot clone files")
        )
        let clean = CommandBarWorktreeCreationResolution.dispatch(
            .init(kind: .cleanCheckout, sourceWorktreeId: sourceId, branchName: branchName))

        for modifier in [EnterModifier.plain, .command, .option] {
            #expect(CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: modifier) == clean)
        }
        #expect(CommandBarWorktreeCreationResolver.footerHints(for: draft).map(\.id) == ["create-clean"])
    }

    @Test("available fork keeps Return on fork and Option-Return on clean checkout")
    func availableForkKeepsForkDefault() throws {
        let sourceId = UUIDv7.generate()
        let branchName = try WorktreeBranchName.validated("feature/available").get()
        let draft = CommandBarWorktreeCreationDraft(
            sourceWorktreeId: sourceId, branchName: .success(branchName), forkEligibility: .available)

        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: .plain)
                == .dispatch(.init(kind: .fork, sourceWorktreeId: sourceId, branchName: branchName)))
        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: .option)
                == .dispatch(.init(kind: .cleanCheckout, sourceWorktreeId: sourceId, branchName: branchName)))
        #expect(
            CommandBarWorktreeCreationResolver.footerHints(for: draft).map(\.id) == ["create-fork", "create-clean"])
    }

    @Test("the Create row shows Fork while eligibility is pending, then the clean fallback once unavailable")
    func createRowFollowsEligibilityAnswer() async throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let eligibility = RecordingForkEligibilityChecker(
            answer: .unavailable(reason: "the volume cannot clone files"))
        let controller = Self.makeController(
            store: fixture.store, dispatcher: dispatcher, worktreeForkEligibility: eligibility)
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        controller.state.rawInput = "feature/eligibility"

        let pendingRow = try #require(
            Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)
        await awaitForkEligibility(of: fixture.worktree.id, in: controller.state)
        let answeredRow = try #require(
            Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)
        controller.executeItem(answeredRow, modifier: .plain)

        #expect(pendingRow.secondaryLine?.text == AppCommand.forkWorktree.definition.helpText)
        #expect(
            answeredRow.secondaryLine?.text
                == "Create clean worktree — fork unavailable here: the volume cannot clone files")
        #expect(
            await eligibility.queries == [
                ForkEligibilityQuery(
                    sourceWorktreePath: fixture.worktree.path,
                    destinationDirectory: fixture.worktree.path.standardizedFileURL.deletingLastPathComponent()
                )
            ])
        #expect(dispatcher.worktreeCreationDispatches.map(\.kind) == [.cleanCheckout])
    }

    @Test("an available answer keeps the fork cue and Return dispatches a fork")
    func availableAnswerDispatchesFork() async throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let controller = Self.makeController(
            store: fixture.store, dispatcher: dispatcher,
            worktreeForkEligibility: RecordingForkEligibilityChecker(answer: .available))
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        controller.state.rawInput = "feature/forked"

        await awaitForkEligibility(of: fixture.worktree.id, in: controller.state)
        let row = try #require(
            Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)
        controller.executeItem(row, modifier: .plain)

        #expect(row.secondaryLine?.text == AppCommand.forkWorktree.definition.helpText)
        #expect(dispatcher.worktreeCreationDispatches.map(\.kind) == [.fork])
    }

    @Test("while eligibility is pending, Fork Returns wait and Option-Return creates a clean checkout now")
    func pendingEligibilityHoldsForkReturns() throws {
        let sourceId = UUIDv7.generate()
        let branchName = try WorktreeBranchName.validated("feature/pending").get()
        let pending = CommandBarWorktreeCreationDraft(sourceWorktreeId: sourceId, branchName: .success(branchName))

        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: pending, modifier: .plain) == .awaitingForkEligibility)
        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: pending, modifier: .command) == .awaitingForkEligibility)
        #expect(
            CommandBarWorktreeCreationResolver.resolve(draft: pending, modifier: .option)
                == .dispatch(.init(kind: .cleanCheckout, sourceWorktreeId: sourceId, branchName: branchName)))
    }

    @Test(
        "Return while eligibility is pending dispatches nothing until the answer, then the answered command",
        arguments: [
            (WorktreeForkEligibility.available, WorktreeCreationKind.fork),
            (WorktreeForkEligibility.unavailable(reason: "the volume cannot clone files"), .cleanCheckout),
        ]
    )
    func pendingReturnDispatchesAfterAnswer(
        answer: WorktreeForkEligibility,
        expectedKind: WorktreeCreationKind
    ) async throws {
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let gate = GatedForkEligibilityChecker()
        let controller = Self.makeController(
            store: fixture.store, dispatcher: dispatcher, worktreeForkEligibility: gate)
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        controller.state.rawInput = "feature/pending"
        let pendingRow = try #require(
            Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)

        controller.executeItem(pendingRow, modifier: .plain)
        let dispatchesBeforeAnswer = dispatcher.worktreeCreationDispatches
        await gate.answer(answer)
        await controller.pendingWorktreeCreation?.value

        #expect(dispatchesBeforeAnswer.isEmpty)
        #expect(dispatcher.worktreeCreationDispatches.map(\.kind) == [expectedKind])
    }

    @Test("an eligibility query from a dismissed bar neither answers nor blocks the reopened bar's query")
    func reopenedBarIssuesItsOwnEligibilityQuery() async throws {
        // Arrange
        let fixture = Self.makeFixture()
        let dispatcher = FakeAppCommandDispatcher()
        let checker = SequencedForkEligibilityChecker()
        let controller = Self.makeController(
            store: fixture.store, dispatcher: dispatcher, worktreeForkEligibility: checker)
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        await checker.awaitQueries(count: 1)
        controller.dismiss()
        try Self.openBranchLevel(controller: controller, store: fixture.store, source: fixture.worktree)
        controller.state.rawInput = "feature/reopened"
        let pendingRow = try #require(
            Self.snapshot(controller: controller, store: fixture.store, dispatcher: dispatcher).displayedItems.first)

        // Act: Return waits; the dismissed session's answer arrives first, then the reopened one's.
        controller.executeItem(pendingRow, modifier: .plain)
        await checker.answerQuery(at: 0, with: .available)
        await checker.answerQuery(at: 1, with: .unavailable(reason: "the volume cannot clone files"))
        await controller.pendingWorktreeCreation?.value

        // Assert: the reopened bar asked again, and only its answer (unavailable) chose the command.
        #expect(await checker.arrivedQueryCount == 2)
        #expect(dispatcher.worktreeCreationDispatches.map(\.kind) == [.cleanCheckout])
    }

    // MARK: - Fixtures

    private static func makeFixture() -> (store: WorkspaceStore, worktree: Worktree) {
        let store = WorkspaceStore()
        let repositoryPath = URL(filePath: "/tmp/command-bar-worktree-creation-\(UUIDv7.generate().uuidString)")
        let repository = store.addRepo(at: repositoryPath)
        let worktree = Worktree(repoId: repository.id, name: "main", path: repositoryPath, isMainWorktree: true)
        store.reconcileDiscoveredWorktrees(repository.id, worktrees: [worktree])
        guard
            let resolvedWorktree = store.repositoryTopologyAtom.repo(repository.id)?.worktrees
                .first(where: \.isMainWorktree)
        else {
            preconditionFailure("Expected repository fixture to retain a main worktree")
        }
        return (store, resolvedWorktree)
    }

    private static func makeController(
        store: WorkspaceStore,
        dispatcher: any AppCommandDispatching,
        worktreeForkEligibility: (any WorktreeForkEligibilityChecking)? = nil
    ) -> CommandBarPanelController {
        CommandBarPanelController(
            store: store,
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher,
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            worktreeForkEligibility: worktreeForkEligibility
        )
    }

    private static func snapshot(
        controller: CommandBarPanelController,
        store: WorkspaceStore,
        dispatcher: any AppCommandDispatching
    ) -> CommandBarResultSnapshot {
        CommandBarResultSession(store: store, repoCache: RepoCacheAtom(), dispatcher: dispatcher)
            .snapshot(state: controller.state)
    }

    private static func openBranchLevel(
        controller: CommandBarPanelController,
        store: WorkspaceStore,
        source: Worktree
    ) throws {
        controller.state.show(prefix: ">")
        let rootItems = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )
        controller.executeItem(try #require(rootItems.first { $0.id == "cmd-newWorktree" }))
        let sourceLevel = try #require(controller.state.currentLevel)
        #expect(sourceLevel.id == "level-newWorktree-source")
        let sourceRow = try #require(
            sourceLevel.items.first { $0.id == "target-worktree-creation-source-\(source.id.uuidString)" }
        )
        controller.executeItem(sourceRow)
    }
}

private struct ForkEligibilityQuery: Equatable {
    let sourceWorktreePath: URL
    let destinationDirectory: URL
}

private actor RecordingForkEligibilityChecker: WorktreeForkEligibilityChecking {
    private let answer: WorktreeForkEligibility
    private(set) var queries: [ForkEligibilityQuery] = []

    init(answer: WorktreeForkEligibility) {
        self.answer = answer
    }

    func forkEligibility(sourceWorktreePath: URL, destinationDirectory: URL) async -> WorktreeForkEligibility {
        queries.append(
            ForkEligibilityQuery(sourceWorktreePath: sourceWorktreePath, destinationDirectory: destinationDirectory))
        return answer
    }
}

/// Awaits observed changes to the bar's eligibility answers until one exists for the
/// source; each wake is a state mutation, never a scheduler turn.
@MainActor
private func awaitForkEligibility(of sourceWorktreeId: UUID, in state: CommandBarState) async {
    while state.forkEligibilityBySourceWorktreeId[sourceWorktreeId] == nil {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = state.forkEligibilityBySourceWorktreeId
            } onChange: {
                continuation.resume()
            }
        }
    }
}

/// Holds the eligibility answer until the test releases it; an answer released before the
/// query arrives is kept and returned when it does.
private actor GatedForkEligibilityChecker: WorktreeForkEligibilityChecking {
    private var waiter: CheckedContinuation<WorktreeForkEligibility, Never>?
    private var releasedAnswer: WorktreeForkEligibility?

    func forkEligibility(sourceWorktreePath _: URL, destinationDirectory _: URL) async -> WorktreeForkEligibility {
        if let releasedAnswer { return releasedAnswer }
        return await withCheckedContinuation { waiter = $0 }
    }

    func answer(_ eligibility: WorktreeForkEligibility) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: eligibility)
        } else {
            releasedAnswer = eligibility
        }
    }
}

/// Numbers eligibility queries in arrival order and parks each until the test answers it
/// by number; an answer given before its query arrives is kept and returned on arrival.
/// Lets a test hold queries from different bar sessions and answer them in a chosen order.
private actor SequencedForkEligibilityChecker: WorktreeForkEligibilityChecking {
    private(set) var arrivedQueryCount = 0
    private var parkedQueriesByIndex: [Int: CheckedContinuation<WorktreeForkEligibility, Never>] = [:]
    private var earlyAnswersByIndex: [Int: WorktreeForkEligibility] = [:]
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func forkEligibility(sourceWorktreePath _: URL, destinationDirectory _: URL) async -> WorktreeForkEligibility {
        let index = arrivedQueryCount
        arrivedQueryCount += 1
        resumeArrivalWaiters()
        if let earlyAnswer = earlyAnswersByIndex.removeValue(forKey: index) {
            return earlyAnswer
        }
        return await withCheckedContinuation { parkedQueriesByIndex[index] = $0 }
    }

    func awaitQueries(count: Int) async {
        guard arrivedQueryCount < count else { return }
        await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
    }

    func answerQuery(at index: Int, with eligibility: WorktreeForkEligibility) {
        if let parkedQuery = parkedQueriesByIndex.removeValue(forKey: index) {
            parkedQuery.resume(returning: eligibility)
        } else {
            earlyAnswersByIndex[index] = eligibility
        }
    }

    private func resumeArrivalWaiters() {
        let arrived = arrivalWaiters.filter { $0.count <= arrivedQueryCount }
        arrivalWaiters.removeAll { $0.count <= arrivedQueryCount }
        arrived.forEach { $0.continuation.resume() }
    }
}
