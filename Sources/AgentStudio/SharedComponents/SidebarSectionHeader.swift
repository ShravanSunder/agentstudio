import AgentStudioInfrastructure
import SwiftUI

package struct SidebarSectionHeaderRow<Content: View, TrailingContent: View>: View {
    let isCollapsed: Bool
    let onToggle: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailingContent: () -> TrailingContent

    package init(
        isCollapsed: Bool,
        onToggle: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.content = content
        self.trailingContent = trailingContent
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
            if let onToggle {
                Button(action: onToggle) {
                    HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
                        collapseIndicator
                        content()
                        Spacer(minLength: AppStyles.General.Spacing.standard)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                collapseIndicator
                content()
                Spacer(minLength: AppStyles.General.Spacing.standard)
            }

            trailingContent()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapseIndicator: some View {
        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
            .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: AppStyles.Shell.Sidebar.sectionHeaderChevronColumnWidth, alignment: .center)
    }
}

extension SidebarSectionHeaderRow where TrailingContent == EmptyView {
    package init(
        isCollapsed: Bool,
        onToggle: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
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
