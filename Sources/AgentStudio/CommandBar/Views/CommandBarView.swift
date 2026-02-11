import SwiftUI

// MARK: - CommandBarView

/// Root SwiftUI view for the command bar. Composes search field, scope pill,
/// results list, and footer. Bound to CommandBarState.
struct CommandBarView: View {
    @Bindable var state: CommandBarState
    let store: WorkspaceStore
    let dispatcher: CommandDispatcher
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Scope pill (only when nested)
            if state.isNested {
                HStack {
                    CommandBarScopePill(
                        parent: state.scopePillParent,
                        child: state.scopePillChild,
                        onDismiss: { state.popToRoot() }
                    )
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Search field with keyboard interception
            CommandBarSearchField(
                state: state,
                onArrowUp: { state.moveSelectionUp(totalItems: totalItems) },
                onArrowDown: { state.moveSelectionDown(totalItems: totalItems) },
                onEnter: { executeSelected() },
                onBackspaceOnEmpty: { handleBackspace() }
            )

            // Separator
            Divider()
                .opacity(0.3)

            // Results list
            CommandBarResultsList(
                groups: groups,
                selectedIndex: state.selectedIndex,
                searchQuery: state.searchQuery,
                dimmedItemIds: dimmedItemIds,
                onSelect: { item in executeItem(item) }
            )

            // Separator
            Divider()
                .opacity(0.3)

            // Footer
            CommandBarFooter(
                isNested: state.isNested,
                selectedHasChildren: selectedItem?.hasChildren ?? false
            )
        }
        .frame(width: 540)
    }

    // MARK: - Data

    private var allItems: [CommandBarItem] {
        if let level = state.currentLevel {
            return level.items
        }
        return CommandBarDataSource.items(scope: state.activeScope, store: store, dispatcher: dispatcher)
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

    private var totalItems: Int {
        filteredItems.count
    }

    private var selectedItem: CommandBarItem? {
        guard state.selectedIndex >= 0, state.selectedIndex < filteredItems.count else { return nil }
        return filteredItems[state.selectedIndex]
    }

    /// IDs of items that should be dimmed (command not currently dispatchable).
    private var dimmedItemIds: Set<String> {
        var ids = Set<String>()
        for item in filteredItems {
            if case .dispatch(let command) = item.action, !dispatcher.canDispatch(command) {
                ids.insert(item.id)
            }
        }
        return ids
    }

    // MARK: - Actions

    private func executeSelected() {
        guard let item = selectedItem else { return }
        executeItem(item)
    }

    private func executeItem(_ item: CommandBarItem) {
        state.recordRecent(itemId: item.id)

        switch item.action {
        case .dispatch(let command):
            onDismiss()
            dispatcher.dispatch(command)

        case .dispatchTargeted(let command, let target, let targetType):
            onDismiss()
            dispatcher.dispatch(command, target: target, targetType: targetType)

        case .navigate(let level):
            state.pushLevel(level)

        case .custom(let closure):
            onDismiss()
            closure()
        }
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
