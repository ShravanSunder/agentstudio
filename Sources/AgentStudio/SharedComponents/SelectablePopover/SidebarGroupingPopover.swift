import SwiftUI

struct SidebarGroupingPopover<Item: Hashable>: View {
    let items: [Item]
    let selectedItem: Item
    let icon: (Item) -> CommandIcon
    let label: (Item) -> String
    let onSelect: (Item) -> Void
    let onDismiss: () -> Void
    @State private var highlightedItem: Item?

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.tight) {
            ForEach(items, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    HStack(spacing: AppStyles.General.Spacing.standard) {
                        Image(systemName: "checkmark")
                            .opacity(selectedItem == item ? 1 : 0)
                            .frame(width: AppStyles.General.Icon.compact)
                        icon(item)
                            .swiftUIImage(size: AppStyles.General.Icon.compact)
                            .frame(width: AppStyles.General.Icon.compact)
                        Text(label(item))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, AppStyles.Shell.Sidebar.ToolbarControl.popoverRowHorizontalPadding)
                    .padding(.vertical, AppStyles.Shell.Sidebar.ToolbarControl.popoverRowVerticalPadding)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(
                            cornerRadius: AppStyles.Shell.Sidebar.ToolbarControl.popoverRowCornerRadius
                        )
                        .fill(
                            Color.primary.opacity(
                                highlightedItem == item ? AppStyles.General.Fill.hover : 0
                            )
                        )
                    )
                }
                .buttonStyle(.plain)
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
        .padding(AppStyles.General.Spacing.tight)
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
