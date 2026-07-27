import AgentStudioInfrastructure
import SwiftUI

package struct SidebarGroupRow: View {
    let octiconLoader: OcticonLoader
    let repoTitle: String
    let organizationName: String?

    package init(
        octiconLoader: OcticonLoader,
        repoTitle: String,
        organizationName: String?
    ) {
        self.octiconLoader = octiconLoader
        self.repoTitle = repoTitle
        self.organizationName = organizationName
    }

    package var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
            AppEntityIcon.repo.swiftUIImage(
                loader: octiconLoader,
                size: AppStyles.Shell.Sidebar.groupIconSize
            )

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
