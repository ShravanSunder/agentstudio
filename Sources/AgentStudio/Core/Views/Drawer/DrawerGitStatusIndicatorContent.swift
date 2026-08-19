import AgentStudioInfrastructure
import SwiftUI

/// Paint-only content for the drawer's passive Git fact cluster. Placement, tooltip anchoring, and
/// accessibility bridging stay with `DrawerIconBar`; this view owns only compact glyph/text paint.
struct DrawerGitStatusIndicatorContent: View {
    let presentation: PaneSurfaceGitStatusPresentation
    let octiconLoader: OcticonLoader

    var body: some View {
        HStack(spacing: AppStyles.Shell.DrawerToolbar.statusClusterSpacing) {
            if presentation.linesAdded != nil
                || presentation.linesDeleted != nil
                || presentation.showsUntrackedFiles
            {
                workingTreeStatus
            }

            if let commitsAhead = presentation.commitsAhead {
                syncStatus(iconName: "octicon-arrow-up", count: commitsAhead)
            }
            if let commitsBehind = presentation.commitsBehind {
                syncStatus(iconName: "octicon-arrow-down", count: commitsBehind)
            }
        }
        .font(
            .system(
                size: AppStyles.Shell.DrawerToolbar.statusFontSize,
                weight: .medium
            )
            .monospacedDigit()
        )
        .lineLimit(1)
    }

    private var workingTreeStatus: some View {
        HStack(spacing: AppStyles.Shell.DrawerToolbar.statusValueSpacing) {
            OcticonImage(
                name: "octicon-dot-fill",
                size: AppStyles.Shell.DrawerToolbar.statusIconSize,
                loader: octiconLoader
            )
            .foregroundStyle(
                AppStyles.Shell.Sidebar.chipDangerColor.opacity(
                    AppStyles.Shell.Sidebar.chipForegroundOpacity
                )
            )

            if let linesAdded = presentation.linesAdded {
                Text("+\(linesAdded)")
                    .foregroundStyle(
                        AppStyles.Shell.Sidebar.chipSuccessColor.opacity(
                            AppStyles.Shell.Sidebar.chipForegroundOpacity
                        )
                    )
            }
            if let linesDeleted = presentation.linesDeleted {
                Text("-\(linesDeleted)")
                    .foregroundStyle(
                        AppStyles.Shell.Sidebar.chipDangerColor.opacity(
                            AppStyles.Shell.Sidebar.chipForegroundOpacity
                        )
                    )
            }
            if presentation.showsUntrackedFiles {
                Text("untracked")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func syncStatus(iconName: String, count: Int) -> some View {
        HStack(spacing: AppStyles.Shell.DrawerToolbar.statusValueSpacing) {
            OcticonImage(
                name: iconName,
                size: AppStyles.Shell.DrawerToolbar.statusIconSize,
                loader: octiconLoader
            )
            Text("\(count)")
        }
        .foregroundStyle(
            AppStyles.Shell.Sidebar.chipInfoColor.opacity(
                AppStyles.Shell.Sidebar.chipForegroundOpacity
            )
        )
    }
}
