import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer command presentation")
struct RepoExplorerCommandPresentationTests {
    @Test("context menu filters worktree and repo commands by their exact target kinds")
    func contextMenuFiltersExactTargetKinds() {
        let dispatcher = RecordingRepoExplorerCommandDispatcher()
        let worktreeId = UUID()
        let repoId = UUID()
        dispatcher.enabledTargetedCommands = [
            .init(command: .openWorktree, target: worktreeId, targetType: .worktree),
            .init(command: .addRepoFavorite, target: repoId, targetType: .repo),
        ]

        let worktreeCommands = RepoExplorerCommandPresentation.targetedCommands(
            [.openWorktree, .addRepoFavorite, .watchFolder],
            surface: .contextMenu,
            target: worktreeId,
            targetType: .worktree,
            dispatcher: dispatcher
        )
        let repoCommands = RepoExplorerCommandPresentation.targetedCommands(
            [.openWorktree, .addRepoFavorite, .watchFolder],
            surface: .contextMenu,
            target: repoId,
            targetType: .repo,
            dispatcher: dispatcher
        )

        #expect(worktreeCommands.map(\.command) == [.openWorktree])
        #expect(repoCommands.map(\.command) == [.addRepoFavorite])
    }

    @Test("inline favorite presentation accepts only the repo target")
    func inlineFavoritePresentationAcceptsOnlyRepoTarget() {
        let dispatcher = RecordingRepoExplorerCommandDispatcher()
        let repoId = UUID()
        dispatcher.enabledTargetedCommands = [
            .init(command: .removeRepoFavorite, target: repoId, targetType: .repo)
        ]

        let repoCommands = RepoExplorerCommandPresentation.targetedCommands(
            [.removeRepoFavorite],
            surface: .inlineControl,
            target: repoId,
            targetType: .repo,
            dispatcher: dispatcher
        )
        let worktreeCommands = RepoExplorerCommandPresentation.targetedCommands(
            [.removeRepoFavorite],
            surface: .inlineControl,
            target: repoId,
            targetType: .worktree,
            dispatcher: dispatcher
        )

        #expect(repoCommands.map(\.command) == [.removeRepoFavorite])
        #expect(worktreeCommands.isEmpty)
    }

    @Test("toolbar filters grouping visibility and sort through contextual inline presentation")
    func toolbarFiltersContextualInlineCommands() {
        let dispatcher = RecordingRepoExplorerCommandDispatcher()
        dispatcher.enabledContextualCommands = [
            .setRepoSidebarGroupingRepo,
            .setRepoSidebarGroupingPane,
            .setRepoSidebarGroupingTab,
            .setRepoSidebarVisibilityMode,
            .setRepoSidebarSortOrder,
        ]

        let commands = RepoExplorerCommandPresentation.contextualCommands(
            [
                .setRepoSidebarGroupingRepo,
                .setRepoSidebarGroupingPane,
                .setRepoSidebarGroupingTab,
                .setRepoSidebarVisibilityMode,
                .setRepoSidebarSortOrder,
                .removeRepo,
            ],
            surface: .inlineControl,
            commandContext: .empty,
            dispatcher: dispatcher
        )

        #expect(
            commands.map(\.command) == [
                .setRepoSidebarGroupingRepo,
                .setRepoSidebarGroupingPane,
                .setRepoSidebarGroupingTab,
                .setRepoSidebarVisibilityMode,
                .setRepoSidebarSortOrder,
            ])
    }

    @Test("typed request capability overrides parameterless command capability")
    func typedRequestCapabilityOverridesParameterlessCommandCapability() throws {
        let dispatcher = RecordingRepoExplorerCommandDispatcher()

        let commands = RepoExplorerCommandPresentation.contextualCommands(
            [.setRepoSidebarVisibilityMode],
            surface: .inlineControl,
            commandContext: .empty,
            dispatcher: dispatcher,
            capabilityOverrides: [.setRepoSidebarVisibilityMode: true]
        )

        let command = try #require(commands.first)
        #expect(command.isEnabled)
        #expect(dispatcher.contextualCapabilityQueries.isEmpty)
    }

    @Test("toolbar capability evaluates the exact next argument values")
    func toolbarCapabilityEvaluatesExactNextArgumentValues() {
        var observedVisibilityModes: [RepoExplorerVisibilityMode] = []
        var observedSortOrders: [RepoExplorerSortOrder] = []

        let capabilities = RepoExplorerView.argumentCommandCapabilities(
            nextVisibilityMode: .favoritesOnly,
            nextSortOrder: .descending,
            canSetVisibilityMode: { mode in
                observedVisibilityModes.append(mode)
                return mode == .favoritesOnly
            },
            canSetSortOrder: { order in
                observedSortOrders.append(order)
                return order == .descending
            }
        )

        #expect(observedVisibilityModes == [.favoritesOnly])
        #expect(observedSortOrders == [.descending])
        #expect(capabilities[.setRepoSidebarVisibilityMode] == true)
        #expect(capabilities[.setRepoSidebarSortOrder] == true)
    }

    @Test("presentation-denied commands are omitted before capability is queried")
    func presentationDeniedCommandsAreOmittedBeforeCapabilityQuery() {
        let dispatcher = RecordingRepoExplorerCommandDispatcher()
        let worktreeId = UUID()

        let commands = RepoExplorerCommandPresentation.targetedCommands(
            [.openWorktreeInPane, .addRepoFavorite, .watchFolder],
            surface: .inlineControl,
            target: worktreeId,
            targetType: .worktree,
            dispatcher: dispatcher
        )

        #expect(commands.isEmpty)
        #expect(dispatcher.targetedCapabilityQueries.isEmpty)
    }

    @Test("presented targeted commands preserve disabled capability state")
    func presentedTargetedCommandsPreserveDisabledCapabilityState() {
        let dispatcher = RecordingRepoExplorerCommandDispatcher()
        let worktreeId = UUID()

        let commands = RepoExplorerCommandPresentation.targetedCommands(
            [.openWorktree],
            surface: .contextMenu,
            target: worktreeId,
            targetType: .worktree,
            dispatcher: dispatcher
        )

        #expect(commands.count == 1)
        #expect(commands.first?.isEnabled == false)
        #expect(
            dispatcher.targetedCapabilityQueries == [
                .init(command: .openWorktree, target: worktreeId, targetType: .worktree)
            ])
    }
}

private struct TargetedCapabilityQuery: Equatable, Hashable {
    let command: AppCommand
    let target: UUID
    let targetType: SearchItemType
}

@MainActor
private final class RecordingRepoExplorerCommandDispatcher: AppCommandDispatching {
    var enabledContextualCommands: Set<AppCommand> = []
    var enabledTargetedCommands: Set<TargetedCapabilityQuery> = []
    private(set) var contextualCapabilityQueries: [AppCommand] = []
    private(set) var targetedCapabilityQueries: [TargetedCapabilityQuery] = []

    func dispatch(_: AppCommand) {}

    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}

    func canDispatch(_ command: AppCommand) -> Bool {
        contextualCapabilityQueries.append(command)
        return enabledContextualCommands.contains(command)
    }

    func canDispatch(
        _ command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) -> Bool {
        let query = TargetedCapabilityQuery(
            command: command,
            target: target,
            targetType: targetType
        )
        targetedCapabilityQueries.append(query)
        return enabledTargetedCommands.contains(query)
    }

    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? {
        nil
    }

    func dispatchMovePaneToTab(
        sourcePaneId _: UUID,
        sourceTabId _: UUID?,
        targetTabId _: UUID
    ) {}
}
