import SwiftUI

struct ManagementPaneIdentityStrip: View {
    let context: PaneManagementContext

    var body: some View {
        VStack(spacing: 8) {
            Text(context.title)
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .lineLimit(1)

            Text(context.detailLine)
                .font(.system(size: AppStyle.sidebarBranchFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let statusChips = context.statusChips {
                WorkspaceStatusChipRow(model: statusChips, accentColor: .accentColor)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppStyle.spacingLoose)
        .padding(.top, AppStyle.spacingLoose)
        .padding(.bottom, 1)
    }
}
