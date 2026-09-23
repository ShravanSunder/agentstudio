import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
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
        let draft = CommandBarWorktreeCreationDraft(sourceWorktreeId: sourceId, branchName: .success(branchName))

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
        dispatcher: any AppCommandDispatching
    ) -> CommandBarPanelController {
        CommandBarPanelController(
            store: store,
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher,
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom()
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
