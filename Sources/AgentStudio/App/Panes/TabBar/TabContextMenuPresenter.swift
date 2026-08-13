import AgentStudioCore
import AppKit

@MainActor
final class TabContextMenuPresenter: NSObject {
    private var actionsByTag: [Int: () -> Void] = [:]
    private var nextActionTag = 0

    func present(
        clickedTabIsSplit: Bool,
        event: NSEvent,
        in view: NSView,
        canDispatchCommand: @escaping (AppCommand) -> Bool,
        onCommand: @escaping (AppCommand) -> Void,
        onShowArrangements: @escaping () -> Void
    ) -> Bool {
        let menu = makeMenu(
            clickedTabIsSplit: clickedTabIsSplit,
            canDispatchCommand: canDispatchCommand,
            onCommand: onCommand,
            onShowArrangements: onShowArrangements
        )
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        actionsByTag.removeAll(keepingCapacity: true)
        return true
    }

    func makeMenu(
        clickedTabIsSplit: Bool,
        canDispatchCommand: @escaping (AppCommand) -> Bool,
        onCommand: @escaping (AppCommand) -> Void,
        onShowArrangements: @escaping () -> Void
    ) -> NSMenu {
        actionsByTag.removeAll(keepingCapacity: true)
        nextActionTag = 0

        let presentedCommands = Set(Self.presentedCommands(clickedTabIsSplit: clickedTabIsSplit))
        let menu = makeEmptyMenu()

        addCommand(.renameTab, whenPresentedIn: presentedCommands, to: menu, canDispatchCommand, onCommand)
        addCommand(.closeTab, whenPresentedIn: presentedCommands, to: menu, canDispatchCommand, onCommand) {
            $0.keyEquivalent = "w"
            $0.keyEquivalentModifierMask = .command
        }
        addCommand(.breakUpTab, whenPresentedIn: presentedCommands, to: menu, canDispatchCommand, onCommand)

        menu.addItem(.separator())

        let addTerminalMenu = makeEmptyMenu()
        addCommand(.splitRight, whenPresentedIn: presentedCommands, to: addTerminalMenu, canDispatchCommand, onCommand)
        addCommand(.splitLeft, whenPresentedIn: presentedCommands, to: addTerminalMenu, canDispatchCommand, onCommand)
        addSubmenu(
            addTerminalMenu,
            title: LocalActionSpec.addTerminalToTab.actionSpec.label,
            to: menu
        )

        addCommand(.newFloatingTerminal, whenPresentedIn: presentedCommands, to: menu, canDispatchCommand, onCommand)

        menu.addItem(.separator())

        addCommand(.equalizePanes, whenPresentedIn: presentedCommands, to: menu, canDispatchCommand, onCommand)

        menu.addItem(.separator())

        let arrangementsMenu = makeEmptyMenu()
        addAction(
            title: LocalActionSpec.showArrangements.actionSpec.label,
            isEnabled: true,
            to: arrangementsMenu,
            perform: onShowArrangements
        )
        addCommand(
            .saveArrangement, whenPresentedIn: presentedCommands, to: arrangementsMenu, canDispatchCommand, onCommand)
        addSubmenu(
            arrangementsMenu,
            title: LocalActionSpec.arrangements.actionSpec.label,
            to: menu
        )

        return menu
    }

    static func presentedCommands(clickedTabIsSplit: Bool) -> [AppCommand] {
        let splitCommands: [AppCommand] = clickedTabIsSplit ? [.breakUpTab, .equalizePanes] : []
        let candidates: [AppCommand] =
            [.renameTab, .closeTab] + splitCommands
            + [.splitRight, .splitLeft, .newFloatingTerminal, .saveArrangement]
        return candidates.filter {
            $0.definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .contextMenu,
                    subject: .targeted(.tab)
                )
            )
        }
    }

    private func makeEmptyMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    private func addCommand(
        _ command: AppCommand,
        whenPresentedIn presentedCommands: Set<AppCommand>,
        to menu: NSMenu,
        _ canDispatchCommand: @escaping (AppCommand) -> Bool,
        _ onCommand: @escaping (AppCommand) -> Void,
        configure: (NSMenuItem) -> Void = { _ in }
    ) {
        guard presentedCommands.contains(command) else { return }
        let item = addAction(
            title: command.definition.label,
            isEnabled: canDispatchCommand(command),
            to: menu,
            perform: { onCommand(command) }
        )
        configure(item)
    }

    @discardableResult
    private func addAction(
        title: String,
        isEnabled: Bool,
        to menu: NSMenu,
        perform: @escaping () -> Void
    ) -> NSMenuItem {
        let actionTag = nextActionTag
        nextActionTag += 1
        actionsByTag[actionTag] = perform

        let item = NSMenuItem(
            title: title,
            action: #selector(activateMenuItem(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = actionTag
        item.isEnabled = isEnabled
        menu.addItem(item)
        return item
    }

    private func addSubmenu(_ submenu: NSMenu, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc
    private func activateMenuItem(_ sender: NSMenuItem) {
        actionsByTag[sender.tag]?()
    }
}
