import SwiftUI

// MARK: - CommandBarView

/// Root SwiftUI view for the command bar. Composes search field, results list,
/// and footer. Bound to CommandBarState.
struct CommandBarView: View {
    @Bindable var state: CommandBarState
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let dispatcher: CommandDispatcher
    let notificationInboxCommands: InboxNotificationCommands?
    let onShortcutTrigger: (ShortcutTrigger) -> Bool
    let onExecuteItem: (CommandBarItem, EnterModifier) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CommandBarStatusStrip(
                mode: currentMode,
                context: currentContext
            )

            Divider()
                .opacity(AppStyles.CommandBar.Panel.rootDividerOpacity)

            CommandBarSearchField(
                state: state,
                onArrowUp: { state.moveSelectionUp(totalItems: totalItems) },
                onArrowDown: { state.moveSelectionDown(totalItems: totalItems) },
                onEnter: { modifier in executeSelected(modifier: modifier) },
                onShortcutTrigger: onShortcutTrigger,
                onBackspaceOnEmpty: { handleBackspace() }
            )

            // Separator
            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            // Back row when nested
            if state.isNested {
                CommandBarBackRow(
                    label: state.backRowLabel,
                    onBack: { state.popToRoot() }
                )
            }

            // Results list
            CommandBarResultsList(
                groups: groups,
                selectedIndex: state.selectedIndex,
                searchQuery: state.searchQuery,
                dimmedItemIds: dimmedItemIds,
                onSelect: { item in onExecuteItem(item, .plain) }
            )

            // Separator
            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            // Footer
            CommandBarFooter(
                hints: footerHints
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private var currentMode: CommandBarAppMode {
        atom(\.managementLayer).isActive ? .management : .normal
    }

    private var currentContext: WorkspacePaneFocus {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        return atom(\.workspacePaneFocus).currentFocus(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            workspaceFocusOwner: atom(\.workspaceFocusOwner)
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

    private var totalItems: Int {
        displayedItems.count
    }

    private var selectedItem: CommandBarItem? {
        guard state.selectedIndex >= 0, state.selectedIndex < displayedItems.count else { return nil }
        return displayedItems[state.selectedIndex]
    }

    /// IDs of items that should be dimmed (command not currently dispatchable).
    /// Checks both direct dispatch and navigate (drill-in) items via the `command` property.
    private var dimmedItemIds: Set<String> {
        var ids = Set<String>()
        for item in displayedItems {
            if let command = item.command, !dispatcher.canDispatch(command) {
                ids.insert(item.id)
            }
        }
        return ids
    }

    private var footerHints: [FooterHint] {
        FooterHintBuilder.hints(
            for: selectedItem,
            isNested: state.isNested,
            canOpenInCurrentTab: canOpenWorktreeInCurrentTab,
            scope: state.currentScope
        )
    }

    private var canOpenWorktreeInCurrentTab: Bool {
        let workspaceTab = WorkspaceTabLayoutDerived(
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

    // MARK: - Actions

    private func executeSelected(modifier: EnterModifier = .plain) {
        guard let item = selectedItem else { return }
        onExecuteItem(item, modifier)
    }

    private func handleBackspace() {
        if state.isNested {
            // Pop back to root
            state.popToRoot()
        } else if state.activePrefix != nil {
            // Clear prefix → return to everything scope
            state.rawInput = ""
        }
    }
}
