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
    package static let empty = Self(
        generation: 0,
        results: [:],
        favoriteStateByRepositoryID: [:]
    )

    package let generation: UInt64
    package let results: [RepoExplorerCommandPresentationRequest: Bool]
    package let favoriteStateByRepositoryID: [UUID: Bool]

    package init(
        generation: UInt64,
        results: [RepoExplorerCommandPresentationRequest: Bool],
        favoriteStateByRepositoryID: [UUID: Bool] = [:]
    ) {
        self.generation = generation
        self.results = results
        self.favoriteStateByRepositoryID = favoriteStateByRepositoryID
    }
}

package struct RepoExplorerCommandPresentationTarget: Equatable, Sendable {
    let materializationHostLifetimeID: RepoExplorerMaterializationHostLifetimeID
    let materializationGeneration: UInt64
    let visibleRevision: UInt64
}

package struct RepoExplorerVisibleWorktreeSnapshot: Equatable, Sendable {
    package let target: RepoExplorerCommandPresentationTarget
    package let worktreeIDs: Set<UUID>
    package let repositoryIDs: Set<UUID>
    package let settledUpdateAttemptByRepositoryID: [UUID: UUID]

    package init(
        target: RepoExplorerCommandPresentationTarget,
        worktreeIDs: Set<UUID>,
        repositoryIDs: Set<UUID> = [],
        settledUpdateAttemptByRepositoryID: [UUID: UUID] = [:]
    ) {
        self.target = target
        self.worktreeIDs = worktreeIDs
        self.repositoryIDs = repositoryIDs
        self.settledUpdateAttemptByRepositoryID = settledUpdateAttemptByRepositoryID
    }
}

package struct RepoExplorerCommandPresentationDelta: Equatable, Sendable {
    package let commandGeneration: UInt64
    package let target: RepoExplorerCommandPresentationTarget
    package let snapshot: RepoExplorerCommandPresentationSnapshot
    package let affectedWorktreeIDs: Set<UUID>
    package let affectedRepositoryIDs: Set<UUID>
    package let affectedRequestIdentities: Set<RepoExplorerCommandPresentationRequest>
    package let toolbarChanged: Bool

    package init(
        commandGeneration: UInt64,
        target: RepoExplorerCommandPresentationTarget,
        snapshot: RepoExplorerCommandPresentationSnapshot,
        affectedWorktreeIDs: Set<UUID>,
        affectedRepositoryIDs: Set<UUID>,
        affectedRequestIdentities: Set<RepoExplorerCommandPresentationRequest>,
        toolbarChanged: Bool
    ) {
        precondition(commandGeneration == snapshot.generation)
        self.commandGeneration = commandGeneration
        self.target = target
        self.snapshot = snapshot
        self.affectedWorktreeIDs = affectedWorktreeIDs
        self.affectedRepositoryIDs = affectedRepositoryIDs
        self.affectedRequestIdentities = affectedRequestIdentities
        self.toolbarChanged = toolbarChanged
    }
}

enum RepoExplorerCommandPresentationDeltaDisposition: Equatable {
    case accepted(reboundRowCount: Int)
    case stale(currentVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot)
    case duplicateOrOlderCommandGeneration
}

@MainActor
struct RepoExplorerTableInteractions {
    static let inert = Self(
        onCommandRequest: { _ in },
        onToggleGroup: { _ in },
        onFocusPane: { _ in }
    )

    let onCommandRequest: (RepoExplorerCommandPresentationRequest) -> Void
    let onToggleGroup: (String) -> Void
    let onFocusPane: (UUID) -> Void
}

package struct RepoExplorerPresentedCommand {
    package let request: RepoExplorerCommandPresentationRequest
    package let commandSpec: AppCommandSpec
    package let isEnabled: Bool

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
            request: request,
            commandSpec: request.command.definition,
            isEnabled: isEnabled
        )
    }
}

package struct RepoExplorerRepositoryCommandPresentation {
    package static func request(repoID: UUID) -> RepoExplorerCommandPresentationRequest {
        RepoExplorerCommandPresentationRequest(
            command: .updateRepositoryFacts,
            surface: .inlineControl,
            target: repoID,
            targetType: .repo,
            arguments: .noArguments
        )
    }

    package static func resolve(
        repoID: UUID,
        snapshot: RepoExplorerCommandPresentationSnapshot
    ) -> RepoExplorerPresentedCommand? {
        RepoExplorerCommandPresentation.presentedCommand(
            for: request(repoID: repoID),
            snapshot: snapshot
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
        nextSortOrder _: RepoExplorerSortOrder
    ) -> Set<RepoExplorerCommandPresentationRequest> {
        var requests = Set(
            toolbarCommands.compactMap { command -> RepoExplorerCommandPresentationRequest? in
                guard command != .setRepoSidebarSortOrder else { return nil }
                return RepoExplorerCommandPresentationRequest(
                    command: command,
                    surface: .inlineControl,
                    target: nil,
                    targetType: nil,
                    arguments: .noArguments
                )
            }
        )
        for sortOrder in RepoExplorerSortOrder.allCases {
            requests.insert(
                RepoExplorerCommandPresentationRequest(
                    command: .setRepoSidebarSortOrder,
                    surface: .inlineControl,
                    target: nil,
                    targetType: nil,
                    arguments: .repoSidebarSortOrder(sortOrder)
                )
            )
        }
        return requests
    }

    static func resolve(
        nextSortOrder: RepoExplorerSortOrder,
        snapshot: RepoExplorerCommandPresentationSnapshot
    ) -> Self {
        let presentedCommands = toolbarCommands.compactMap { command in
            let request = RepoExplorerCommandPresentationRequest(
                command: command,
                surface: .inlineControl,
                target: nil,
                targetType: nil,
                arguments: command == .setRepoSidebarSortOrder
                    ? .repoSidebarSortOrder(nextSortOrder)
                    : .noArguments
            )
            return RepoExplorerCommandPresentation.presentedCommand(for: request, snapshot: snapshot)
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
