import SwiftUI

struct SidebarGroupRow: View {
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            OcticonImage(name: "octicon-repo", size: AppStyle.sidebarGroupIconSize)
                .foregroundStyle(.secondary)

            HStack(spacing: AppStyle.sidebarGroupTitleSpacing) {
                Text(repoTitle)
                    .font(.system(size: AppStyle.textLg, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(2)

                if let organizationName, !organizationName.isEmpty {
                    Text("·")
                        .font(.system(size: AppStyle.textSm, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(organizationName)
                        .font(.system(size: AppStyle.sidebarGroupOrganizationFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: AppStyle.sidebarGroupOrganizationMaxWidth, alignment: .leading)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppStyle.sidebarGroupRowVerticalPadding)
        .contentShape(Rectangle())
    }
}

struct SidebarResolvedGroupHeaderRow: View {
    let isExpanded: Bool
    let repoTitle: String
    let organizationName: String?

    var body: some View {
        HStack(spacing: AppStyle.spacingTight) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: AppStyle.textXs, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppStyle.textBase, alignment: .center)

            SidebarGroupRow(
                repoTitle: repoTitle,
                organizationName: organizationName
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
