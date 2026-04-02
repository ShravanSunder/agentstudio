import SwiftUI

struct ManagementPaneIdentityStrip: View {
    let context: PaneManagementContext

    var body: some View {
        VStack(spacing: 8) {
            Text(context.title)
                .font(.system(size: AppStyle.textLg, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(1)

            Text(context.detailLine)
                .font(.system(size: AppStyle.sidebarBranchFontSize, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.92))
                .lineLimit(1)

            if let statusChips = context.statusChips {
                WorkspaceStatusChipRow(model: statusChips, accentColor: .accentColor)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(AppStyle.fillMuted))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(AppStyle.fillActive), lineWidth: 1)
                )
        )
        .padding(.horizontal, AppStyle.spacingLoose)
        .padding(.vertical, AppStyle.spacingLoose)
    }
}
