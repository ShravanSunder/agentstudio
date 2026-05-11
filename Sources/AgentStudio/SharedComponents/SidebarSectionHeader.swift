import SwiftUI

struct SidebarSectionHeader<TrailingContent: View>: View {
    let label: String
    let isCollapsed: Bool
    let onToggle: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyles.General.Typography.textBase, alignment: .center)

                Text(label)
                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: AppStyles.General.Spacing.standard)

                trailingContent()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppStyles.General.Spacing.loose)
            .padding(.vertical, AppStyles.Shell.Sidebar.groupRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SidebarSectionHeader where TrailingContent == EmptyView {
    init(
        label: String,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.label = label
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.trailingContent = { EmptyView() }
    }
}
