import SwiftUI

struct SidebarSectionHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.trailingContent = trailingContent()
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppStyles.General.Spacing.standard) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyles.Shell.Sidebar.groupIconSize)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: AppStyles.General.Typography.textBase, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: AppStyles.Shell.Sidebar.groupOrganizationFontSize))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: AppStyles.General.Spacing.standard)
                trailingContent
            }
            .padding(.vertical, AppStyles.Shell.Sidebar.groupRowVerticalPadding)
            .padding(.horizontal, AppStyles.Shell.Sidebar.rowHorizontalInset)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

extension SidebarSectionHeader where TrailingContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            isExpanded: isExpanded,
            onToggle: onToggle
        ) {
            EmptyView()
        }
    }
}
