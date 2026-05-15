import SwiftUI

struct SidebarGroupRow: View {
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
            AppEntityIcon.repo.swiftUIImage(size: AppStyles.Shell.Sidebar.groupIconSize)

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
