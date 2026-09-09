import AgentStudioInfrastructure
import SwiftUI

package struct SidebarGroupingPopover<Item: Hashable, Icon: View>: View {
    let items: [Item]
    let selectedItem: Item
    let icon: (Item) -> Icon
    let label: (Item) -> String
    let onSelect: (Item) -> Void
    let onDismiss: () -> Void
    @State private var highlightedItem: Item?

    package init(
        items: [Item],
        selectedItem: Item,
        @ViewBuilder icon: @escaping (Item) -> Icon,
        label: @escaping (Item) -> String,
        onSelect: @escaping (Item) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.items = items
        self.selectedItem = selectedItem
        self.icon = icon
        self.label = label
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.tight) {
            ForEach(items, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    PopoverOptionLabel(label(item)) { icon(item) }
                }
                .buttonStyle(
                    PopoverOptionButtonStyle(
                        isSelected: selectedItem == item,
                        isHighlighted: highlightedItem == item
                    )
                )
                .accessibilityLabel(label(item))
                .accessibilityAddTraits(selectedItem == item ? .isSelected : [])
                .onHover { isHovered in
                    if isHovered {
                        highlightedItem = item
                    }
                }
            }
        }
        .frame(minWidth: AppStyles.Shell.Sidebar.ToolbarControl.popoverMinimumWidth)
        .background(
            SelectablePopoverKeyboardBridge(
                items: keyboardItems,
                selectedItemId: highlightedItem,
                auxiliaryAction: nil,
                onSelect: select,
                onHighlight: { highlightedItem = $0 },
                onDismiss: onDismiss,
                matchesAdditionalDismissShortcut: { _ in false }
            )
            .frame(width: 0, height: 0)
        )
        .onAppear(perform: repairHighlight)
        .onChange(of: items) { _, _ in repairHighlight() }
        .onChange(of: selectedItem) { _, _ in repairHighlight() }
        .onExitCommand(perform: onDismiss)
    }

    private var keyboardItems: [SelectablePopoverKeyboardItem<Item>] {
        items.map { SelectablePopoverKeyboardItem(id: $0) }
    }

    private func repairHighlight() {
        highlightedItem = SelectablePopoverKeyboardRouter.defaultSelection(
            items: keyboardItems,
            preferredItemId: selectedItem
        )
    }

    private func select(_ item: Item) {
        highlightedItem = item
        onSelect(item)
    }
}
