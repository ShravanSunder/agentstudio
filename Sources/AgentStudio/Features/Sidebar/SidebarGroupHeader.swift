import SwiftUI

struct SidebarGroupRow: View {
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            OcticonImage(name: "octicon-repo", size: AppStyles.Shell.Sidebar.groupIconSize)
                .foregroundStyle(.secondary)

            HStack(spacing: AppStyles.Shell.Sidebar.groupTitleSpacing) {
                Text(repoTitle)
                    .font(.system(size: AppStyles.General.Typography.textLg, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(2)

                if let organizationName, !organizationName.isEmpty {
                    Text("·")
                        .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(organizationName)
                        .font(.system(size: AppStyles.Shell.Sidebar.groupOrganizationFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: AppStyles.Shell.Sidebar.groupOrganizationMaxWidth, alignment: .leading)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppStyles.Shell.Sidebar.groupRowVerticalPadding)
        .contentShape(Rectangle())
    }
}

struct SidebarResolvedGroupHeaderRow: View {
    let isExpanded: Bool
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.tight) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppStyles.General.Typography.textBase, alignment: .center)

            SidebarGroupRow(
                repoTitle: repoTitle,
                organizationName: organizationName
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
