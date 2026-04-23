import AppKit
import SwiftUI
import os.log

private let controllerLogger = Logger(subsystem: "com.agentstudio", category: "CommandBarPanelController")

// MARK: - CommandBarPanelController

/// Manages the command bar panel lifecycle: show, dismiss, animate, backdrop.
/// Owns the CommandBarState and wires it to the panel.
/// All methods must be called on the main thread (enforced by AppKit caller context).
@MainActor
final class CommandBarPanelController {

    // MARK: - State

    let state = CommandBarState()

    // MARK: - Dependencies

    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let dispatcher: CommandDispatcher
    private let notificationInboxCommands: InboxNotificationCommands?

    // MARK: - Panel

    private var panel: CommandBarPanel?
    private var backdropView: CommandBarBackdropView?

    /// The parent window the command bar is attached to.
    private weak var parentWindow: NSWindow?

    var isKeyWindow: Bool {
        panel?.isKeyWindow == true
    }

    // MARK: - Initialization

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        dispatcher: CommandDispatcher,
        notificationInboxCommands: InboxNotificationCommands? = nil
    ) {
        self.store = store
        self.repoCache = repoCache
        self.dispatcher = dispatcher
        self.notificationInboxCommands = notificationInboxCommands
        state.loadRecents()
    }

    // MARK: - Show / Dismiss

    /// Show the command bar. If already visible with a different prefix, switch in-place.
    /// If already visible with the same prefix (or no prefix), preserve current state.
    func show(parentWindow: NSWindow) {
        show(mode: .defaultScope(.everything), parentWindow: parentWindow)
    }

    func show(prefix: String, parentWindow: NSWindow) {
        show(mode: .prefix(prefix), parentWindow: parentWindow)
    }

    func show(defaultRootScope: CommandBarScope, parentWindow: NSWindow) {
        show(mode: .defaultScope(defaultRootScope), parentWindow: parentWindow)
    }

    private func show(
        mode: CommandBarState.OpenMode,
        parentWindow: NSWindow
    ) {
        self.parentWindow = parentWindow

        if state.isVisible {
            let currentPrefix = normalizedPrefix(for: state.currentScope)
            let normalizedRequestedPrefix: String? =
                switch mode {
                case .prefix(let prefix):
                    normalizedPrefix(for: prefix)
                case .defaultScope:
                    nil
                }

            if currentPrefix == normalizedRequestedPrefix {
                return
            } else {
                switch mode {
                case .prefix(let prefix):
                    state.switchPrefix(prefix)
                case .defaultScope:
                    state.show(defaultScope: defaultRootScope(for: mode))
                }
                return
            }
        }

        // Create panel and backdrop
        switch mode {
        case .prefix(let prefix):
            state.show(prefix: prefix)
        case .defaultScope(let defaultRootScope):
            state.show(defaultScope: defaultRootScope)
        }
        presentPanel(parentWindow: parentWindow)
    }

    /// Dismiss the command bar and clean up.
    func dismiss() {
        guard state.isVisible else { return }

        state.dismiss()
        dismissPanel()
    }

    // MARK: - Panel Presentation

    private func presentPanel(parentWindow: NSWindow) {
        let panel = CommandBarPanel()
        self.panel = panel

        // Wire Escape key through controller dismiss lifecycle
        panel.onDismiss = { [weak self] in
            self?.dismiss()
        }
        // The panel is the primary shortcut ingress because performKeyEquivalent
        // fires before menu handling while the command bar is key. The view/text
        // field also receives this closure as a fallback for selector-driven
        // NSTextField command paths like modified Enter.
        panel.onShortcutTrigger = { [weak self] trigger in
            guard let self else { return false }
            return self.handleShortcutTrigger(trigger)
        }

        // Set SwiftUI content
        let contentView = CommandBarView(
            state: state,
            store: store,
            repoCache: repoCache,
            dispatcher: dispatcher,
            notificationInboxCommands: notificationInboxCommands,
            onShortcutTrigger: { [weak self] trigger in
                self?.handleShortcutTrigger(trigger) ?? false
            },
            onExecuteItem: { [weak self] item, modifier in
                self?.executeItem(item, modifier: modifier)
            }
        )
        panel.setContent(contentView)

        // Add as child window
        parentWindow.addChildWindow(panel, ordered: .above)

        // Position panel
        panel.positionRelativeTo(parentWindow: parentWindow)

        // Initial size — will be updated by content
        panel.updateHeight(parentWindow: parentWindow)

        // Show backdrop
        showBackdrop(on: parentWindow)

        // Animate in
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })

        controllerLogger.debug("Command bar panel presented")
    }

    private var currentContext: CommandContext {
        let workspaceTab = WorkspaceTabDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return atom(\.commandContext).currentFocus(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom
        )
    }

    private var allItems: [CommandBarItem] {
        if let level = state.currentLevel {
            return level.items
        }
        return CommandBarDataSource.items(
            scope: state.activeScope,
            store: store,
            repoCache: repoCache,
            dispatcher: dispatcher,
            focus: currentContext,
            notificationInboxCommands: notificationInboxCommands
        )
    }

    private var filteredItems: [CommandBarItem] {
        CommandBarSearch.filter(
            items: allItems,
            query: state.searchQuery,
            recentIds: state.recentItemIds
        )
    }

    private var groups: [CommandBarItemGroup] {
        CommandBarDataSource.grouped(filteredItems)
    }

    private var displayedItems: [CommandBarItem] {
        CommandBarDataSource.displayItems(from: groups)
    }

    private var selectedItem: CommandBarItem? {
        guard state.selectedIndex >= 0, state.selectedIndex < displayedItems.count else { return nil }
        return displayedItems[state.selectedIndex]
    }

    private var canOpenWorktreeInCurrentTab: Bool {
        let workspaceTab = WorkspaceTabDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        guard
            let activeTabId = store.tabShellAtom.activeTabId,
            let activeTab = workspaceTab.tab(activeTabId),
            activeTab.activePaneId != nil
        else {
            return false
        }
        return true
    }

    private func handleShortcutTrigger(_ trigger: ShortcutTrigger) -> Bool {
        switch CommandBarShortcutRouter.route(
            trigger: trigger,
            selectedItem: selectedItem,
            displayedItems: displayedItems
        ) {
        case .dismiss:
            dismiss()
            return true
        case .showPrefix(let prefix):
            guard let parentWindow else { return false }
            if let prefix {
                show(prefix: prefix, parentWindow: parentWindow)
            } else {
                show(parentWindow: parentWindow)
            }
            return true
        case .executeRow(let item):
            executeItem(item)
            return true
        case .executeSelected(let modifier):
            guard let selectedItem else { return false }
            executeItem(selectedItem, modifier: modifier)
            return true
        case .unhandled:
            return false
        }
    }

    private func defaultRootScope(for mode: CommandBarState.OpenMode) -> CommandBarScope {
        switch mode {
        case .prefix:
            return .everything
        case .defaultScope(let scope):
            return scope
        }
    }

    private func executeItem(_ item: CommandBarItem, modifier: EnterModifier = .plain) {
        if let command = item.command, !dispatcher.canDispatch(command) {
            return
        }

        switch item.action {
        case .dispatch(let command):
            state.recordRecent(itemId: item.id)
            dismiss()
            dispatcher.dispatch(command)
        case .dispatchTargeted(let command, let target, let targetType):
            state.recordRecent(itemId: item.id)
            dismiss()
            dispatcher.dispatch(command, target: target, targetType: targetType)
        case .navigate(let level):
            state.pushLevel(level)
        case .custom(let closure):
            state.recordRecent(itemId: item.id)
            dismiss()
            closure()
        case .worktreeAction(let presence):
            executeResolvedWorktreeAction(
                resolution: CommandBarWorktreeActionResolver.resolve(
                    presence: presence,
                    modifier: modifier,
                    canOpenInCurrentTab: canOpenWorktreeInCurrentTab
                ),
                presence: presence,
                itemId: item.id
            )
        }
    }

    private func executeResolvedWorktreeAction(
        resolution: CommandBarWorktreeActionResolution,
        presence: WorktreePresence,
        itemId: String
    ) {
        switch resolution {
        case .dispatch(let command, let target, let targetType):
            state.recordRecent(itemId: itemId)
            dismiss()
            dispatcher.dispatch(command, target: target, targetType: targetType)
        case .showActionsMenu:
            state.pushLevel(
                CommandBarDataSource.buildWorktreeActionsLevel(
                    presence: presence,
                    canOpenInCurrentTab: canOpenWorktreeInCurrentTab
                )
            )
        }
    }

    private func dismissPanel() {
        guard let panel else { return }

        // Animate out — capture panel locally to avoid actor-isolation issues in completion
        let panelToRemove = panel
        self.panel = nil

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panelToRemove.animator().alphaValue = 0
            },
            completionHandler: {
                Task { @MainActor in
                    panelToRemove.parent?.removeChildWindow(panelToRemove)
                    panelToRemove.orderOut(nil)
                    controllerLogger.debug("Command bar panel dismissed")
                }
            })

        // Remove backdrop
        hideBackdrop()

        // Return focus to parent window
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    private func normalizedPrefix(for prefix: String?) -> String? {
        if let prefix, [">", "$", "#"].contains(prefix) {
            return prefix + " "
        }
        return prefix
    }

    private func normalizedPrefix(for scope: CommandBarScope) -> String? {
        switch scope {
        case .everything:
            return nil
        case .commands:
            return "> "
        case .panes:
            return "$ "
        case .repos:
            return "# "
        case .inbox:
            return nil
        }
    }

    // MARK: - Backdrop

    private func showBackdrop(on window: NSWindow) {
        guard let contentView = window.contentView else { return }

        let backdrop = CommandBarBackdropView(onDismiss: { [weak self] in
            self?.dismiss()
        })
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.alphaValue = 0
        contentView.addSubview(backdrop, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        self.backdropView = backdrop

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            backdrop.animator().alphaValue = 1
        }
    }

    private func hideBackdrop() {
        guard let backdrop = backdropView else { return }

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                backdrop.animator().alphaValue = 0
            },
            completionHandler: {
                Task { @MainActor in
                    backdrop.removeFromSuperview()
                }
            })
        backdropView = nil
    }
}

// MARK: - CommandBarBackdropView

/// Semi-transparent overlay behind the command bar panel. Click to dismiss.
@MainActor
final class CommandBarBackdropView: NSView {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("CommandBarPanelController does not support NSCoder") }

    override func mouseDown(with event: NSEvent) {
        onDismiss()
    }

    // The backdrop lives in the parent window, but the command bar panel is
    // key while open. Without this, a click outside the panel would first
    // promote the parent window to key and swallow the event — requiring a
    // second click to actually dismiss.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
