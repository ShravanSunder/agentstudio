import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

struct ManagementPaneIdentityCardBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct ManagementPaneIdentityStrip: View {
    let context: PaneManagementContext
    let octiconLoader: OcticonLoader

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(context.identityRows) { row in
                HStack(spacing: AppStyles.General.Spacing.tight) {
                    rowIcon(for: row.icon)
                        .foregroundStyle(.secondary.opacity(0.92))
                        .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

                    Text(caption(for: row))
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.72))
                        .textCase(.uppercase)
                        .fixedSize()

                    Text(row.text)
                        .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.92))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help(row.toolTip ?? row.text)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: row))
            }

            if let statusChips = context.statusChips {
                WorkspaceStatusChipRow(
                    octiconLoader: octiconLoader,
                    model: statusChips,
                    accentColor: AppStyles.General.Accent.primaryColor
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(AppStyles.General.Fill.muted))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(AppStyles.General.Fill.active), lineWidth: 1)
                )
        )
        .anchorPreference(
            key: ManagementPaneIdentityCardBoundsPreferenceKey.self,
            value: .bounds,
            transform: { $0 }
        )
        .background {
            AccessibilityLabelBridge(
                identifier: "paneManagement.identityStrip",
                label: context.identityRows.map(\.text).joined(separator: ", ")
            )
        }
        .padding(.horizontal, AppStyles.General.Spacing.loose)
        .padding(.vertical, AppStyles.General.Spacing.loose)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func rowIcon(for icon: PaneManagementIcon) -> some View {
        switch icon {
        case .octicon(let name):
            OcticonImage(
                name: name,
                size: AppStyles.Shell.Sidebar.branchIconSize,
                loader: octiconLoader
            )
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: AppStyles.Shell.Sidebar.branchIconSize, weight: .medium))
        }
    }

    private func accessibilityLabel(for row: PaneManagementIdentityRow) -> String {
        switch row.id {
        case "repo":
            return "Repo \(row.text)"
        case "branch":
            return "Branch \(row.text)"
        case "worktree":
            return "Worktree \(row.text)"
        case "cwd":
            return "Current directory \(row.text)"
        case "note":
            return "Note \(row.text)"
        default:
            return row.text
        }
    }

    private func caption(for row: PaneManagementIdentityRow) -> String {
        switch row.id {
        case "repo":
            return "repo"
        case "branch":
            return "branch"
        case "worktree":
            return "worktree"
        case "cwd":
            return "cwd"
        case "note":
            return "note"
        default:
            return ""
        }
    }
}

struct ManagementPaneIdentityOverlay: View {
    let context: PaneManagementContext
    let octiconLoader: OcticonLoader

    var body: some View {
        ManagementPaneIdentityStrip(
            context: context,
            octiconLoader: octiconLoader
        )
        .frame(maxWidth: .infinity)
        .background(AppStyles.Shell.PaneChrome.background)
    }
}
