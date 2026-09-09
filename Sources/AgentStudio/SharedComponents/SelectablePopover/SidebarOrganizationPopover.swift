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
package struct SidebarOrganizationPopover<Item: Hashable, Icon: View, HeaderIcon: View, UnavailableIcon: View>: View {
    let model: SidebarOrganizationPopoverModel<Item>
    let subgroupTitle: String
    let unavailableSubgroupText: String
    @ViewBuilder let unavailableSubgroupIcon: () -> UnavailableIcon
    @ViewBuilder let icon: (Item) -> Icon
    @ViewBuilder let headerIcon: (SidebarOrganizationLevel) -> HeaderIcon
    let onSelect: (SidebarOrganizationPopoverItem<Item>) -> Void
    let onDismiss: () -> Void
    @State private var highlightedItem: SidebarOrganizationPopoverItem<Item>?

    package init(
        group: SidebarOrganizationPopoverSection<Item>,
        subgroup: SidebarOrganizationPopoverSection<Item>?,
        subgroupTitle: String,
        unavailableSubgroupText: String,
        @ViewBuilder unavailableSubgroupIcon: @escaping () -> UnavailableIcon,
        @ViewBuilder icon: @escaping (Item) -> Icon,
        @ViewBuilder headerIcon: @escaping (SidebarOrganizationLevel) -> HeaderIcon,
        onSelect: @escaping (SidebarOrganizationPopoverItem<Item>) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.model = SidebarOrganizationPopoverModel(group: group, subgroup: subgroup)
        self.subgroupTitle = subgroupTitle
        self.unavailableSubgroupText = unavailableSubgroupText
        self.unavailableSubgroupIcon = unavailableSubgroupIcon
        self.icon = icon
        self.headerIcon = headerIcon
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    package var body: some View {
        HStack(alignment: .top, spacing: AppStyles.Components.SidebarOrganizationPanel.columnSpacing) {
            section(model.group, level: .group)
            if let subgroup = model.subgroup {
                section(subgroup, level: .subgroup)
            } else {
                unavailableSubgroupSection
            }
        }
        .padding(AppStyles.Components.SidebarOrganizationPanel.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
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

    private func section(
        _ section: SidebarOrganizationPopoverSection<Item>,
        level: SidebarOrganizationLevel
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.loose) {
            sectionHeader(section.title, level: level)

            VStack(spacing: AppStyles.General.Spacing.tight) {
                ForEach(section.options.filter(\.isEnabled)) { option in
                    optionButton(option, section: section, level: level)
                }
            }
        }
        .frame(width: AppStyles.Components.SidebarOrganizationPanel.columnWidth, alignment: .topLeading)
    }

    private func sectionHeader(_ title: String, level: SidebarOrganizationLevel) -> some View {
        SidebarPopoverSectionHeader(title) { headerIcon(level) }
    }

    private var unavailableSubgroupSection: some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.loose) {
            sectionHeader(subgroupTitle, level: .subgroup)
            HStack(spacing: AppStyles.General.Spacing.standard) {
                unavailableSubgroupIcon()
                    .frame(width: AppStyles.General.Icon.compact, height: AppStyles.General.Icon.compact)
                    .accessibilityHidden(true)
                Text(unavailableSubgroupText)
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, AppStyles.General.Spacing.loose)
            .padding(.vertical, AppStyles.General.Spacing.tight)
        }
        .frame(width: AppStyles.Components.SidebarOrganizationPanel.columnWidth, alignment: .topLeading)
    }

    private func optionButton(
        _ option: SidebarToolbarSegment<Item>,
        section: SidebarOrganizationPopoverSection<Item>,
        level: SidebarOrganizationLevel
    ) -> some View {
        let item = SidebarOrganizationPopoverItem(level: level, value: option.value)
        let isSelected = section.selection == option.value
        return Button {
            select(item)
        } label: {
            HStack(spacing: AppStyles.General.Spacing.standard) {
                icon(option.value)
                    .frame(width: AppStyles.General.Icon.compact, height: AppStyles.General.Icon.compact)
                Text(option.label)
                    .font(
                        .system(
                            size: AppStyles.General.Typography.textXs,
                            weight: isSelected ? .semibold : .regular
                        )
                    )
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(
            SidebarOrganizationOptionStyle(
                isSelected: isSelected, isHighlighted: highlightedItem == item
            )
        )
        .accessibilityLabel(option.label)
        .accessibilityIdentifier(option.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .controlHelp(option.tooltipValue)
        .onHover { isHovered in
            if isHovered { highlightedItem = item }
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

private struct SidebarOrganizationOptionStyle: ButtonStyle {
    let isSelected: Bool
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isEmphasized = isSelected || isHighlighted || configuration.isPressed
        let fillOpacity =
            configuration.isPressed
            ? AppStyles.General.Fill.pressed
            : isSelected
                ? AppStyles.General.Fill.active
                : isHighlighted ? AppStyles.General.Fill.hover : AppStyles.General.Fill.subtle
        configuration.label
            .foregroundStyle(isEmphasized ? .primary : .secondary)
            .padding(.horizontal, AppStyles.General.Spacing.loose)
            .padding(.vertical, AppStyles.General.Spacing.tight)
            .background(
                RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.bar)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .contentShape(Rectangle())
    }
}
