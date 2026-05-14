import SwiftUI

struct SidebarSectionHeaderRow<Content: View, TrailingContent: View>: View {
    let isCollapsed: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailingContent: () -> TrailingContent

    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.tight) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppStyles.General.Typography.textBase, alignment: .center)

            content()

            Spacer(minLength: AppStyles.General.Spacing.standard)

            trailingContent()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SidebarSectionHeaderRow where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.content = content
        self.trailingContent = { EmptyView() }
    }
}

struct SidebarSectionHeader<LabelContent: View, TrailingContent: View>: View {
    let isCollapsed: Bool
    let onToggle: () -> Void
    @ViewBuilder let label: () -> LabelContent
    @ViewBuilder let trailingContent: () -> TrailingContent

    static var chromePolicy: SidebarHeaderChromePolicy {
        .plainSectionHeader
    }

    var body: some View {
        Button(action: onToggle) {
            SidebarSectionHeaderRow(isCollapsed: isCollapsed) {
                label()
            } trailingContent: {
                trailingContent()
            }
            .padding(.horizontal, AppStyles.General.Spacing.loose)
            .padding(.vertical, AppStyles.Shell.Sidebar.groupRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SidebarSectionHeaderTextLabel: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

extension SidebarSectionHeader where LabelContent == SidebarSectionHeaderTextLabel, TrailingContent == EmptyView {
    init(
        label: String,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.label = {
            SidebarSectionHeaderTextLabel(label: label)
        }
        self.trailingContent = { EmptyView() }
    }
}

extension SidebarSectionHeader where TrailingContent == EmptyView {
    init(
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.label = label
        self.trailingContent = { EmptyView() }
    }
}
