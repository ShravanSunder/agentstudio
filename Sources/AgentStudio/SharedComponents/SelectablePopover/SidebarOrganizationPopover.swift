import AgentStudioInfrastructure
import SwiftUI

package enum SidebarOrganizationLevel: Hashable {
    case group
    case subgroup
}

package struct SidebarOrganizationPopoverSection<Item: Hashable> {
    package let title: String
    package let options: [SidebarToolbarSegment<Item>]
    package let selection: Item

    package init(title: String, options: [SidebarToolbarSegment<Item>], selection: Item) {
        self.title = title
        self.options = options
        self.selection = selection
    }
}

package struct SidebarOrganizationPopoverItem<Item: Hashable>: Hashable {
    package let level: SidebarOrganizationLevel
    package let value: Item

    package init(level: SidebarOrganizationLevel, value: Item) {
        self.level = level
        self.value = value
    }
}

package struct SidebarOrganizationPopoverModel<Item: Hashable> {
    package let group: SidebarOrganizationPopoverSection<Item>
    package let subgroup: SidebarOrganizationPopoverSection<Item>?

    package init(
        group: SidebarOrganizationPopoverSection<Item>,
        subgroup: SidebarOrganizationPopoverSection<Item>?
    ) {
        self.group = group
        self.subgroup = subgroup
    }

    package var keyboardItems: [SelectablePopoverKeyboardItem<SidebarOrganizationPopoverItem<Item>>] {
        rows.map { SelectablePopoverKeyboardItem(id: $0) }
    }

    package var preferredKeyboardItem: SidebarOrganizationPopoverItem<Item> {
        SidebarOrganizationPopoverItem(level: .group, value: group.selection)
    }

    package func selectionRequest(
        for item: SidebarOrganizationPopoverItem<Item>
    ) -> SidebarOrganizationPopoverItem<Item>? {
        rows.contains(item) ? item : nil
    }

    private var rows: [SidebarOrganizationPopoverItem<Item>] {
        let groupRows = group.options.filter(\.isEnabled).map {
            SidebarOrganizationPopoverItem(level: .group, value: $0.value)
        }
        let subgroupRows =
            subgroup?.options.filter(\.isEnabled).map {
                SidebarOrganizationPopoverItem(level: .subgroup, value: $0.value)
            } ?? []
        return groupRows + subgroupRows
    }
}

@MainActor
package struct SidebarOrganizationPopover<Item: Hashable, Icon: View>: View {
    let model: SidebarOrganizationPopoverModel<Item>
    @ViewBuilder let icon: (Item) -> Icon
    let onSelect: (SidebarOrganizationPopoverItem<Item>) -> Void
    let onDismiss: () -> Void
    @State private var highlightedItem: SidebarOrganizationPopoverItem<Item>?

    package init(
        group: SidebarOrganizationPopoverSection<Item>,
        subgroup: SidebarOrganizationPopoverSection<Item>?,
        @ViewBuilder icon: @escaping (Item) -> Icon,
        onSelect: @escaping (SidebarOrganizationPopoverItem<Item>) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.model = SidebarOrganizationPopoverModel(group: group, subgroup: subgroup)
        self.icon = icon
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.tight) {
            section(model.group, level: .group)
            if let subgroup = model.subgroup {
                Divider()
                section(subgroup, level: .subgroup)
            }
        }
        .frame(minWidth: AppStyles.Shell.Sidebar.ToolbarControl.popoverMinimumWidth)
        .padding(AppStyles.General.Spacing.tight)
        .background(
            SelectablePopoverKeyboardBridge(
                items: model.keyboardItems,
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
        .onChange(of: model.keyboardItems.map(\.id)) { _, _ in repairHighlight() }
        .onExitCommand(perform: onDismiss)
    }

    @ViewBuilder
    private func section(
        _ section: SidebarOrganizationPopoverSection<Item>,
        level: SidebarOrganizationLevel
    ) -> some View {
        Text(section.title)
            .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppStyles.Shell.Sidebar.ToolbarControl.popoverRowHorizontalPadding)

        ForEach(section.options.filter(\.isEnabled)) { option in
            let item = SidebarOrganizationPopoverItem(level: level, value: option.value)
            Button {
                select(item)
            } label: {
                HStack(spacing: AppStyles.General.Spacing.standard) {
                    Image(systemName: "checkmark")
                        .opacity(section.selection == option.value ? 1 : 0)
                        .frame(width: AppStyles.General.Icon.compact)
                    icon(option.value)
                        .frame(width: AppStyles.General.Icon.compact)
                    Text(option.label)
                        .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
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
            .accessibilityLabel(option.label)
            .accessibilityIdentifier(option.accessibilityIdentifier)
            .accessibilityAddTraits(section.selection == option.value ? .isSelected : [])
            .controlHelp(option.tooltipValue)
            .onHover { isHovered in
                if isHovered { highlightedItem = item }
            }
        }
    }

    private func repairHighlight() {
        highlightedItem = SelectablePopoverKeyboardRouter.defaultSelection(
            items: model.keyboardItems,
            preferredItemId: highlightedItem ?? model.preferredKeyboardItem
        )
    }

    private func select(_ item: SidebarOrganizationPopoverItem<Item>) {
        guard let request = model.selectionRequest(for: item) else { return }
        highlightedItem = request
        onSelect(request)
    }
}

package struct SidebarPopoverReveal<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var isVisible = false

    package init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    package var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -AppStyles.General.Spacing.tight)
            .onAppear {
                withAnimation(.easeOut(duration: AppStyles.General.Animation.fast)) {
                    isVisible = true
                }
            }
    }
}
