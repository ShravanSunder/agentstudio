import SwiftUI

// MARK: - CommandBarView

/// Root SwiftUI view for the command bar. Composes search field, results list,
/// and footer. Bound to CommandBarState.
struct CommandBarView: View {
    @Bindable var state: CommandBarState
    let resultSession: CommandBarResultSession
    let onShortcutTrigger: (ShortcutTrigger) -> Bool
    let onExecuteItem: (CommandBarItem, EnterModifier) -> Void

    var body: some View {
        let resultSnapshot = resultSession.snapshot(state: state)
        return VStack(spacing: 0) {
            CommandBarStatusStrip(
                mode: resultSnapshot.currentMode,
                context: resultSnapshot.currentContext
            )

            Divider()
                .opacity(AppStyles.CommandBar.Panel.rootDividerOpacity)

            CommandBarSearchField(
                state: state,
                onArrowUp: { state.moveSelectionUp(totalItems: resultSnapshot.totalItems) },
                onArrowDown: { state.moveSelectionDown(totalItems: resultSnapshot.totalItems) },
                onEnter: { modifier in executeSelected(modifier: modifier) },
                onShortcutTrigger: onShortcutTrigger,
                onBackspaceOnEmpty: { handleBackspace() },
                onTabForward: { handleTabForward() },
                onShiftTabBack: { state.popLevel() }
            )

            // Separator
            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            // Breadcrumb trail when nested
            if state.isNested {
                CommandBarBreadcrumbRow(
                    labels: state.breadcrumbLabels,
                    onNavigate: { index in state.navigateToBreadcrumb(at: index) }
                )
            }

            // Results list
            CommandBarResultsList(
                groups: resultSnapshot.groups,
                selectedIndex: state.selectedIndex,
                searchQuery: state.isNested ? state.searchQuery : state.normalizedRootQuery,
                dimmedItemIds: resultSnapshot.dimmedItemIds,
                onSelect: { item in onExecuteItem(item, .plain) }
            )

            // Separator
            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            // Footer
            CommandBarFooter(
                hints: resultSnapshot.footerHints
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func executeSelected(modifier: EnterModifier = .plain) {
        guard let item = resultSession.snapshot(state: state).selectedItem else { return }
        onExecuteItem(item, modifier)
    }

    private func handleTabForward() {
        guard
            let item = resultSession.snapshot(state: state).selectedItem,
            item.hasChildren
        else { return }
        onExecuteItem(item, .plain)
    }

    private func handleBackspace() {
        if state.isNested {
            state.popLevel()
        } else if state.activePrefix != nil {
            // Clear prefix → return to everything scope
            state.rawInput = ""
        }
    }
}
