import AgentStudioCore
import Foundation

package enum RepoExplorerCommandPresentationArguments: Hashable, Sendable {
    case noArguments
    case repoSidebarSortOrder(RepoExplorerSortOrder)
}

package struct RepoExplorerCommandPresentationRequest: Hashable, Sendable {
    package let command: AppCommand
    package let surface: AppCommandSurface
    package let target: UUID?
    package let targetType: SearchItemType?
    package let arguments: RepoExplorerCommandPresentationArguments

    package init(
        command: AppCommand,
        surface: AppCommandSurface,
        target: UUID?,
        targetType: SearchItemType?,
        arguments: RepoExplorerCommandPresentationArguments
    ) {
        self.command = command
        self.surface = surface
        self.target = target
        self.targetType = targetType
        self.arguments = arguments
    }
}

package struct RepoExplorerCommandPresentationSnapshot: Equatable, Sendable {
    package static let empty = Self(generation: 0, results: [:])

    package let generation: UInt64
    package let results: [RepoExplorerCommandPresentationRequest: Bool]

    package init(
        generation: UInt64,
        results: [RepoExplorerCommandPresentationRequest: Bool]
    ) {
        self.generation = generation
        self.results = results
    }
}

struct RepoExplorerPresentedCommand {
    let commandSpec: AppCommandSpec
    let isEnabled: Bool

    var command: AppCommand {
        commandSpec.command
    }
}

enum RepoExplorerCommandPresentation {
    static func presentedCommand(
        for request: RepoExplorerCommandPresentationRequest,
        snapshot: RepoExplorerCommandPresentationSnapshot
    ) -> RepoExplorerPresentedCommand? {
        guard let isEnabled = snapshot.results[request] else { return nil }
        return RepoExplorerPresentedCommand(
            commandSpec: request.command.definition,
            isEnabled: isEnabled
        )
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

    package static func requests(
        worktreeId: UUID,
        repoId: UUID,
        isFavorite: Bool,
        showsFavoriteControl: Bool
    ) -> Set<RepoExplorerCommandPresentationRequest> {
        let favoriteCommand: AppCommand = isFavorite ? .removeRepoFavorite : .addRepoFavorite
        var requests = Set(
            contextMenuWorktreeCommands.map { command in
                RepoExplorerCommandPresentationRequest(
                    command: command,
                    surface: .contextMenu,
                    target: worktreeId,
                    targetType: .worktree,
                    arguments: .noArguments
                )
            }
        )
        requests.insert(
            RepoExplorerCommandPresentationRequest(
                command: .openWorktree,
                surface: .inlineControl,
                target: worktreeId,
                targetType: .worktree,
                arguments: .noArguments
            )
        )
        if showsFavoriteControl {
            for surface in [AppCommandSurface.contextMenu, .inlineControl] {
                requests.insert(
                    RepoExplorerCommandPresentationRequest(
                        command: favoriteCommand,
                        surface: surface,
                        target: repoId,
                        targetType: .repo,
                        arguments: .noArguments
                    )
                )
            }
        }
        return requests
    }

    static func resolve(
        worktreeId: UUID,
        repoId: UUID,
        isFavorite: Bool,
        showsFavoriteControl: Bool,
        snapshot: RepoExplorerCommandPresentationSnapshot
    ) -> Self {
        let presentedCommands = requests(
            worktreeId: worktreeId,
            repoId: repoId,
            isFavorite: isFavorite,
            showsFavoriteControl: showsFavoriteControl
        ).compactMap { request -> (RepoExplorerCommandPresentationRequest, RepoExplorerPresentedCommand)? in
            RepoExplorerCommandPresentation.presentedCommand(for: request, snapshot: snapshot)
                .map { (request, $0) }
        }

        return Self(
            contextMenuCommandsByIdentity: Self.index(
                presentedCommands.compactMap { request, command in
                    request.surface == .contextMenu ? command : nil
                }
            ),
            inlineCommandsByIdentity: Self.index(
                presentedCommands.compactMap { request, command in
                    request.surface == .inlineControl ? command : nil
                }
            )
        )
    }

    func contextMenuCommand(_ command: AppCommand) -> RepoExplorerPresentedCommand? {
        contextMenuCommandsByIdentity[command]
    }

    static func contextMenuLabel(for command: AppCommand) -> String? {
        switch command {
        case .openNewTerminalInTab, .openWorktreeInPane:
            return "Terminal"
        case .openBridgeReviewInNewTab, .showBridgeReview:
            return "Review"
        case .openBridgeFilesInNewTab, .showBridgeFiles:
            return "Files"
        default:
            return nil
        }
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

package struct RepoExplorerToolbarCommandPresentation {
    private static let toolbarCommands: [AppCommand] = [
        .setRepoSidebarGroupingRepo,
        .setRepoSidebarGroupingPane,
        .setRepoSidebarGroupingTab,
        .setRepoSidebarSortOrder,
    ]

    private let commandsByIdentity: [AppCommand: RepoExplorerPresentedCommand]

    package static func requests(
        nextSortOrder: RepoExplorerSortOrder
    ) -> Set<RepoExplorerCommandPresentationRequest> {
        Set(
            toolbarCommands.map { command in
                let arguments: RepoExplorerCommandPresentationArguments =
                    switch command {
                    case .setRepoSidebarSortOrder:
                        .repoSidebarSortOrder(nextSortOrder)
                    default:
                        .noArguments
                    }
                return RepoExplorerCommandPresentationRequest(
                    command: command,
                    surface: .inlineControl,
                    target: nil,
                    targetType: nil,
                    arguments: arguments
                )
            })
    }

    static func resolve(
        nextSortOrder: RepoExplorerSortOrder,
        snapshot: RepoExplorerCommandPresentationSnapshot
    ) -> Self {
        let presentedCommands = requests(
            nextSortOrder: nextSortOrder
        ).compactMap { request in
            RepoExplorerCommandPresentation.presentedCommand(for: request, snapshot: snapshot)
        }
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
