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
        case .pane(let pane):
            return makePaneMenu(rowID: row.id, pane: pane, snapshot: commandPresentationSnapshot)
        case .activitySubgroup, .sectionHeader, .loadingSectionHeader, .loadingRepository,
            .unassociatedPane, .topologyFault, .unresolved:
            return nil
        }
    }

    private func makePaneMenu(
        rowID: RepoExplorerRowID,
        pane: RepoExplorerProjectedPaneRow,
        snapshot: RepoExplorerCommandPresentationSnapshot
    ) -> NSMenu {
        let requests = RepoExplorerPaneCommandPresentation.requests(
            paneId: pane.destination.paneId, isPinned: pane.isPinned,
            worktreeId: pane.destination.worktreeId
        )
        func presentation(_ command: AppCommand) -> RepoExplorerPresentedCommand? {
            guard let request = requests.first(where: { $0.command == command }) else { return nil }
            return RepoExplorerCommandPresentation.presentedCommand(for: request, snapshot: snapshot)
        }
        return makeItemMenu(
            ItemMenu(
                rowID: rowID,
                location: "Tab \(pane.destination.tabIndex + 1) · Pane \(pane.destination.paneIndexInTab + 1)",
                command: presentation,
                navigation: .pane,
                pin: pane.isPinned ? .unpinPane : .pinPane,
                editor: presentation(.copyCurrentPanePath)?.isEnabled == true ? .pane(pane.destination.paneId) : nil,
                path: .pane
            ))
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
        let isPinned =
            commandPresentationSnapshot.pinnedStateByRepositoryID[worktree.repo.id] ?? false
        let pinnedControlVisibility = RepoExplorerPinnedControlVisibility(
            isMainWorktree: worktree.isMainCheckout
        )
        let commandPresentation = RepoExplorerWorktreeCommandPresentation.resolve(
            worktreeId: worktree.worktree.id,
            repoId: worktree.repo.id,
            isPinned: isPinned,
            showsPinnedControl: pinnedControlVisibility.showsContextMenuAction,
            snapshot: commandPresentationSnapshot
        )
        return makeItemMenu(
            ItemMenu(
                rowID: rowID, location: nil,
                command: commandPresentation.contextMenuCommand,
                navigation: .worktree(worktree.paneDestinations),
                pin: isPinned ? .unpinRepo : .pinRepo,
                editor: .worktree(worktree.worktree.path),
                path: .worktree(worktree.worktree.path)
            ))
    }

    private struct ItemMenu {
        enum Navigation {
            case pane
            case worktree([RepoExplorerPaneDestination])
        }
        enum Editor {
            case pane(UUID)
            case worktree(URL)
        }
        enum PathTarget {
            case pane
            case worktree(URL)
        }
        let rowID: RepoExplorerRowID
        let location: String?
        let command: (AppCommand) -> RepoExplorerPresentedCommand?
        let navigation: Navigation
        let pin: AppCommand
        let editor: Editor?
        let path: PathTarget
    }

    /// Both row kinds supply targets; this owner fixes action order and section boundaries.
    private func makeItemMenu(_ item: ItemMenu) -> NSMenu {
        let menu = makeEmptyMenu()
        addCommandSubmenu(
            action: .createNewInTab,
            commands: [.openNewTerminalInTab, .openBridgeReviewInNewTab, .openBridgeFilesInNewTab].map(item.command),
            rowID: item.rowID, to: menu
        )
        addCommandSubmenu(
            action: .createNewInPane,
            commands: [.openWorktreeInPane, .showBridgeReview, .showBridgeFiles].map(item.command),
            rowID: item.rowID, to: menu
        )
        switch item.navigation {
        case .pane:
            for command: AppCommand in [.zoomPane, .editPaneNote] {
                if let action = item.command(command) { addCommand(action, rowID: item.rowID, to: menu) }
            }
        case .worktree(let destinations):
            addPaneDestinationSubmenu(destinations, rowID: item.rowID, to: menu)
        }
        addSeparatorIfNeeded(to: menu)
        if let pin = item.command(item.pin) { addCommand(pin, rowID: item.rowID, to: menu) }
        if let editor = item.editor {
            let editorMenu = makeEmptyMenu()
            for (spec, target) in [
                (LocalActionSpec.openInCursor, ExternalEditorTarget.cursor.id),
                (.openInVSCode, ExternalEditorTarget.vscode.id),
            ] {
                addLocalAction(spec, rowID: item.rowID, to: editorMenu) { [interactions] in
                    switch editor {
                    case .pane(let paneID): interactions.onOpenPaneInEditor(paneID, target)
                    case .worktree(let path): _ = ExternalWorkspaceOpener.openInEditor(id: target, path: path)
                    }
                }
            }
            addSubmenu(editorMenu, actionSpec: LocalActionSpec.openInEditorMenu.actionSpec, to: menu)
        }
        addSeparatorIfNeeded(to: menu)
        switch item.path {
        case .pane:
            for command: AppCommand in [.openPaneLocationInFinder, .copyCurrentPanePath] {
                if let action = item.command(command) { addCommand(action, rowID: item.rowID, to: menu) }
            }
        case .worktree(let path):
            addLocalAction(.revealInFinder, rowID: item.rowID, to: menu) { PathActions.revealInFinder(path) }
            addLocalAction(.copyPath, rowID: item.rowID, to: menu) { PathActions.copyPath(path) }
        }
        if let location = item.location {
            addSeparatorIfNeeded(to: menu)
            let label = NSMenuItem(title: location, action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
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
