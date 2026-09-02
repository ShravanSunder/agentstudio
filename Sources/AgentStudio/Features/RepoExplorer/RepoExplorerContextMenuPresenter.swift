import AgentStudioCore
import AgentStudioInfrastructure
import AppKit

@MainActor
final class RepoExplorerContextMenuPresenter: NSObject {
    private let octiconLoader: OcticonLoader
    private let interactions: RepoExplorerTableInteractions
    private let isRowCurrent: (RepoExplorerRowID) -> Bool
    private var actionsByTag: [Int: () -> Void] = [:]
    private var nextActionTag = 0

    init(
        octiconLoader: OcticonLoader,
        interactions: RepoExplorerTableInteractions,
        isRowCurrent: @escaping (RepoExplorerRowID) -> Bool
    ) {
        self.octiconLoader = octiconLoader
        self.interactions = interactions
        self.isRowCurrent = isRowCurrent
    }

    func makeMenu(
        for row: RepoExplorerMaterializedRow,
        commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot
    ) -> NSMenu? {
        actionsByTag.removeAll(keepingCapacity: true)
        nextActionTag = 0

        switch row.presentation {
        case .groupHeader(let group):
            return makeGroupMenu(rowID: row.id, group: group)
        case .worktree(let worktree):
            return makeWorktreeMenu(
                rowID: row.id,
                worktree: worktree,
                commandPresentationSnapshot: commandPresentationSnapshot
            )
        case .sectionHeader, .loadingSectionHeader, .loadingRepository, .pane,
            .unassociatedPane, .topologyFault, .unresolved:
            return nil
        }
    }

    private func makeGroupMenu(
        rowID: RepoExplorerRowID,
        group: RepoExplorerMaterializedGroupHeaderPresentation
    ) -> NSMenu? {
        let menu = makeEmptyMenu()
        addPaneDestinationSubmenu(
            group.paneDestinations,
            rowID: rowID,
            to: menu
        )
        if let path = group.semanticRepoPath {
            addLocalAction(.revealInFinder, rowID: rowID, showsIcon: false, to: menu) {
                PathActions.revealInFinder(path)
            }
            addLocalAction(.copyPath, rowID: rowID, showsIcon: false, to: menu) {
                PathActions.copyPath(path)
            }
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func makeWorktreeMenu(
        rowID: RepoExplorerRowID,
        worktree: RepoExplorerMaterializedWorktreePresentation,
        commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot
    ) -> NSMenu {
        let isFavorite =
            commandPresentationSnapshot.favoriteStateByRepositoryID[worktree.repo.id] ?? false
        let favoriteControlVisibility = RepoExplorerFavoriteControlVisibility(
            isMainWorktree: worktree.isMainCheckout
        )
        let commandPresentation = RepoExplorerWorktreeCommandPresentation.resolve(
            worktreeId: worktree.worktree.id,
            repoId: worktree.repo.id,
            isFavorite: isFavorite,
            showsFavoriteControl: favoriteControlVisibility.showsContextMenuAction,
            snapshot: commandPresentationSnapshot
        )
        let menu = makeEmptyMenu()

        addCommandSubmenu(
            action: .createNewInTab,
            commands: [
                commandPresentation.contextMenuCommand(.openNewTerminalInTab),
                commandPresentation.contextMenuCommand(.openBridgeReviewInNewTab),
                commandPresentation.contextMenuCommand(.openBridgeFilesInNewTab),
            ],
            rowID: rowID,
            to: menu
        )
        addCommandSubmenu(
            action: .createNewInPane,
            commands: [
                commandPresentation.contextMenuCommand(.openWorktreeInPane),
                commandPresentation.contextMenuCommand(.showBridgeReview),
                commandPresentation.contextMenuCommand(.showBridgeFiles),
            ],
            rowID: rowID,
            to: menu
        )
        addPaneDestinationSubmenu(worktree.paneDestinations, rowID: rowID, to: menu)

        addSeparatorIfNeeded(to: menu)
        let favoriteCommand: AppCommand = isFavorite ? .removeRepoFavorite : .addRepoFavorite
        if let favoritePresentation = commandPresentation.contextMenuCommand(favoriteCommand) {
            addCommand(favoritePresentation, rowID: rowID, to: menu)
        }

        let editorMenu = makeEmptyMenu()
        addLocalAction(.openInCursor, rowID: rowID, to: editorMenu) {
            ExternalWorkspaceOpener.openInCursor(worktree.worktree.path)
        }
        addLocalAction(.openInVSCode, rowID: rowID, to: editorMenu) {
            ExternalWorkspaceOpener.openInVSCode(worktree.worktree.path)
        }
        addSubmenu(
            editorMenu,
            actionSpec: LocalActionSpec.openInEditorMenu.actionSpec,
            to: menu
        )

        addSeparatorIfNeeded(to: menu)
        addLocalAction(.revealInFinder, rowID: rowID, to: menu) {
            PathActions.revealInFinder(worktree.worktree.path)
        }
        addLocalAction(.copyPath, rowID: rowID, to: menu) {
            PathActions.copyPath(worktree.worktree.path)
        }
        return menu
    }

    private func addCommandSubmenu(
        action: LocalActionSpec,
        commands: [RepoExplorerPresentedCommand?],
        rowID: RepoExplorerRowID,
        to menu: NSMenu
    ) {
        let presentedCommands = commands.compactMap { $0 }
        guard !presentedCommands.isEmpty else { return }
        let submenu = makeEmptyMenu()
        for command in presentedCommands {
            addCommand(command, rowID: rowID, to: submenu)
        }
        addSubmenu(submenu, actionSpec: action.actionSpec, to: menu)
    }

    private func addCommand(
        _ command: RepoExplorerPresentedCommand,
        rowID: RepoExplorerRowID,
        to menu: NSMenu
    ) {
        let actionSpec = command.commandSpec.actionSpec
        let title =
            RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: command.command)
            ?? actionSpec.label
        addAction(
            title: title,
            icon: actionSpec.icon,
            isEnabled: command.isEnabled,
            rowID: rowID,
            to: menu
        ) { [interactions] in
            interactions.onCommandRequest(command.request)
        }
    }

    private func addPaneDestinationSubmenu(
        _ destinations: [RepoExplorerPaneDestination],
        rowID: RepoExplorerRowID,
        to menu: NSMenu
    ) {
        guard !destinations.isEmpty else { return }
        let submenu = makeEmptyMenu()
        for destination in destinations {
            addAction(
                title: destination.label,
                icon: nil,
                isEnabled: true,
                rowID: rowID,
                to: submenu
            ) { [interactions] in
                interactions.onFocusPane(destination.paneId)
            }
        }
        addSubmenu(
            submenu,
            title: LocalActionSpec.goToPane.actionSpec.label,
            icon: nil,
            to: menu
        )
    }

    private func addLocalAction(
        _ action: LocalActionSpec,
        rowID: RepoExplorerRowID,
        showsIcon: Bool = true,
        to menu: NSMenu,
        perform: @escaping () -> Void
    ) {
        let actionSpec = action.actionSpec
        addAction(
            title: actionSpec.label,
            icon: showsIcon ? actionSpec.icon : nil,
            isEnabled: true,
            rowID: rowID,
            to: menu,
            perform: perform
        )
    }

    private func addAction(
        title: String,
        icon: CommandIcon?,
        isEnabled: Bool,
        rowID: RepoExplorerRowID,
        to menu: NSMenu,
        perform: @escaping () -> Void
    ) {
        let actionTag = nextActionTag
        nextActionTag += 1
        actionsByTag[actionTag] = { [weak self] in
            guard self?.isRowCurrent(rowID) == true else { return }
            perform()
        }

        let item = NSMenuItem(
            title: title,
            action: #selector(activateMenuItem(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = actionTag
        item.isEnabled = isEnabled
        item.image = image(for: icon, accessibilityDescription: title)
        menu.addItem(item)
    }

    private func addSubmenu(_ submenu: NSMenu, actionSpec: ActionSpec, to menu: NSMenu) {
        addSubmenu(submenu, title: actionSpec.label, icon: actionSpec.icon, to: menu)
    }

    private func addSubmenu(
        _ submenu: NSMenu,
        title: String,
        icon: CommandIcon?,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = image(for: icon, accessibilityDescription: title)
        item.submenu = submenu
        menu.addItem(item)
    }

    private func image(
        for icon: CommandIcon?,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let icon else { return nil }
        switch icon {
        case .system:
            return icon.nsImage(accessibilityDescription: accessibilityDescription)
        case .octicon(let symbol):
            return octiconLoader.image(named: symbol.rawValue)
        }
    }

    private func addSeparatorIfNeeded(to menu: NSMenu) {
        guard let lastItem = menu.items.last, !lastItem.isSeparatorItem else { return }
        menu.addItem(.separator())
    }

    private func makeEmptyMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    @objc
    private func activateMenuItem(_ sender: NSMenuItem) {
        actionsByTag[sender.tag]?()
    }
}

@MainActor
final class RepoExplorerTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let clickedRowIndex = row(at: convert(event.locationInWindow, from: nil))
        guard clickedRowIndex >= 0 else { return nil }
        return contextMenuProvider?(clickedRowIndex)
    }
}
