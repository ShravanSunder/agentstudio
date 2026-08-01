import AgentStudioCore
import Foundation

struct RepoExplorerPresentedCommand {
    let commandSpec: AppCommandSpec
    let isEnabled: Bool

    var command: AppCommand {
        commandSpec.command
    }
}

enum RepoExplorerCommandPresentation {
    @MainActor
    static func contextualCommands(
        _ commands: [AppCommand],
        surface: AppCommandSurface,
        commandContext: CommandContext,
        dispatcher: any AppCommandDispatching,
        capabilityOverrides: [AppCommand: Bool] = [:]
    ) -> [RepoExplorerPresentedCommand] {
        commands.compactMap { command in
            let commandSpec = command.definition
            guard
                commandSpec.shouldPresent(
                    AppCommandPresentationQuery(
                        surface: surface,
                        subject: .contextual(commandContext)
                    )
                )
            else {
                return nil
            }

            return RepoExplorerPresentedCommand(
                commandSpec: commandSpec,
                isEnabled: capabilityOverrides[command] ?? dispatcher.canDispatch(command)
            )
        }
    }

    @MainActor
    static func targetedCommands(
        _ commands: [AppCommand],
        surface: AppCommandSurface,
        target: UUID,
        targetType: SearchItemType,
        dispatcher: any AppCommandDispatching
    ) -> [RepoExplorerPresentedCommand] {
        commands.compactMap { command in
            let commandSpec = command.definition
            guard
                commandSpec.shouldPresent(
                    AppCommandPresentationQuery(
                        surface: surface,
                        subject: .targeted(targetType)
                    )
                )
            else {
                return nil
            }

            return RepoExplorerPresentedCommand(
                commandSpec: commandSpec,
                isEnabled: dispatcher.canDispatch(
                    command,
                    target: target,
                    targetType: targetType
                )
            )
        }
    }
}

package struct RepoExplorerWorktreeCommandPresentation {
    package static let notPresented = Self(
        contextMenuCommandsByIdentity: [:],
        inlineCommandsByIdentity: [:]
    )

    private static let contextMenuWorktreeCommands: [AppCommand] = [
        .openWorktree,
        .openWorktreeInPane,
        .showBridgeReview,
        .showBridgeFiles,
        .openNewTerminalInTab,
        .openBridgeReviewInNewTab,
        .openBridgeFilesInNewTab,
    ]

    private let contextMenuCommandsByIdentity: [AppCommand: RepoExplorerPresentedCommand]
    private let inlineCommandsByIdentity: [AppCommand: RepoExplorerPresentedCommand]

    @MainActor
    static func resolve(
        worktreeId: UUID,
        repoId: UUID,
        isFavorite: Bool,
        showsFavoriteControl: Bool,
        dispatcher: any AppCommandDispatching
    ) -> Self {
        let favoriteCommand: AppCommand = isFavorite ? .removeRepoFavorite : .addRepoFavorite
        let contextMenuWorktreeCommands = RepoExplorerCommandPresentation.targetedCommands(
            contextMenuWorktreeCommands,
            surface: .contextMenu,
            target: worktreeId,
            targetType: .worktree,
            dispatcher: dispatcher
        )
        let contextMenuFavoriteCommands =
            showsFavoriteControl
            ? RepoExplorerCommandPresentation.targetedCommands(
                [favoriteCommand],
                surface: .contextMenu,
                target: repoId,
                targetType: .repo,
                dispatcher: dispatcher
            )
            : []
        let inlineWorktreeCommands = RepoExplorerCommandPresentation.targetedCommands(
            [.openWorktree],
            surface: .inlineControl,
            target: worktreeId,
            targetType: .worktree,
            dispatcher: dispatcher
        )
        let inlineFavoriteCommands =
            showsFavoriteControl
            ? RepoExplorerCommandPresentation.targetedCommands(
                [favoriteCommand],
                surface: .inlineControl,
                target: repoId,
                targetType: .repo,
                dispatcher: dispatcher
            )
            : []

        return Self(
            contextMenuCommandsByIdentity: Self.index(
                contextMenuWorktreeCommands + contextMenuFavoriteCommands
            ),
            inlineCommandsByIdentity: Self.index(
                inlineWorktreeCommands + inlineFavoriteCommands
            )
        )
    }

    func contextMenuCommand(_ command: AppCommand) -> RepoExplorerPresentedCommand? {
        contextMenuCommandsByIdentity[command]
    }

    func inlineCommand(_ command: AppCommand) -> RepoExplorerPresentedCommand? {
        inlineCommandsByIdentity[command]
    }

    private static func index(
        _ presentedCommands: [RepoExplorerPresentedCommand]
    ) -> [AppCommand: RepoExplorerPresentedCommand] {
        Dictionary(
            uniqueKeysWithValues: presentedCommands.map { presentedCommand in
                (presentedCommand.command, presentedCommand)
            }
        )
    }
}

struct RepoExplorerToolbarCommandPresentation {
    private static let toolbarCommands: [AppCommand] = [
        .setRepoSidebarGroupingRepo,
        .setRepoSidebarGroupingPane,
        .setRepoSidebarGroupingTab,
        .setRepoSidebarVisibilityMode,
        .setRepoSidebarSortOrder,
    ]

    private let commandsByIdentity: [AppCommand: RepoExplorerPresentedCommand]

    @MainActor
    static func resolve(
        commandContext: CommandContext,
        dispatcher: any AppCommandDispatching,
        capabilityOverrides: [AppCommand: Bool] = [:]
    ) -> Self {
        let presentedCommands = RepoExplorerCommandPresentation.contextualCommands(
            toolbarCommands,
            surface: .inlineControl,
            commandContext: commandContext,
            dispatcher: dispatcher,
            capabilityOverrides: capabilityOverrides
        )
        return Self(
            commandsByIdentity: Dictionary(
                uniqueKeysWithValues: presentedCommands.map { presentedCommand in
                    (presentedCommand.command, presentedCommand)
                }
            )
        )
    }

    func command(_ command: AppCommand) -> RepoExplorerPresentedCommand? {
        commandsByIdentity[command]
    }
}
