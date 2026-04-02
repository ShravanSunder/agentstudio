import SwiftUI

struct ManagementPaneFooter: View {
    let context: PaneManagementContext
    let onOpenFinder: () -> Void
    let onOpenCursor: () -> Void

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.title)
                    .font(.system(size: AppStyle.textXs, weight: .semibold))
                    .lineLimit(1)
                Text(context.subtitle)
                    .font(.system(size: AppStyle.textXs))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppStyle.spacingStandard)

            Button(action: onOpenFinder) {
                Image(systemName: "folder")
                    .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                    .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
            }
            .buttonStyle(.plain)
            .disabled(context.targetPath == nil)
            .help("Open pane location in Finder")

            Button(action: onOpenCursor) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                    .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
            }
            .buttonStyle(.plain)
            .disabled(context.targetPath == nil)
            .help("Open pane location in Cursor")
        }
        .padding(.horizontal, AppStyle.spacingLoose)
        .frame(maxWidth: .infinity)
        .frame(height: DrawerLayout.iconBarFrameHeight)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                .fill(Color.black.opacity(AppStyle.fillMuted))
        )
        .padding(.horizontal, AppStyle.paneGap)
        .padding(.bottom, AppStyle.paneGap)
    }
}
