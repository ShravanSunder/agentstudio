import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

struct RepoExplorerPaneRow: View {
    let row: RepoExplorerProjectedPaneRow
    let octiconLoader: OcticonLoader
    var keyboardPresentation = RepoExplorerRowKeyboardPresentation.inactive
    let onFocus: () -> Void

    @State private var isHovering = false

    var body: some View {
        SidebarRowShell(isSelected: keyboardPresentation.isSelected, isHovering: isHovering) {
            RepoExplorerPaneRowContent(
                primaryText: row.primaryText,
                secondaryLine: row.secondaryLine,
                branchContextText: row.branchContextText,
                branchStatus: row.branchStatus,
                recencyText: row.recencyText,
                recencyTier: row.recencyTier,
                isActive: row.isActive,
                isDrawerPane: row.isDrawerPane,
                octiconLoader: octiconLoader,
                shortcutDisplay: keyboardPresentation.shortcutDisplay
            )
        }
        .onTapGesture(perform: onFocus)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onFocus() }
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            [
                row.primaryText,
                row.secondaryText,
                row.branchContextText,
                row.branchStatus?.prCount.map { "\($0) pull requests" },
                row.isDrawerPane ? "Drawer" : nil,
                row.recencyText,
                row.isActive ? "Active" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

}

struct RepoExplorerPaneRowContent: View {
    let primaryText: String
    let secondaryLine: RepoExplorerPaneSecondaryLine?
    let branchContextText: String?
    let branchStatus: GitBranchStatus?
    let recencyText: String
    let recencyTier: RepoExplorerPaneRecencyTier
    let isActive: Bool
    let isDrawerPane: Bool
    let octiconLoader: OcticonLoader
    var shortcutDisplay: ShortcutDisplayText?

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
                (isDrawerPane ? AppEntityIcon.drawer : .pane).swiftUIImage(
                    loader: octiconLoader,
                    size: AppStyles.Shell.Sidebar.rowIdentityIconSize
                )
                .frame(
                    width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth,
                    alignment: .leading
                )
                .sidebarShortcutHint(shortcutDisplay)
                Text(primaryText)
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let branchContextText {
                SidebarMetadataLine(
                    icon: .octicon(name: "octicon-git-branch", loader: octiconLoader),
                    text: branchContextText
                )
            }
            if let secondaryLine {
                SidebarMetadataLine(
                    icon: .systemName(secondaryLine.iconSystemName),
                    text: secondaryLine.text
                )
                .saturation(secondaryLine.isTerminalOutput ? 0 : 1)
            }
            chipRow
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var chipRow: some View {
        SidebarStatusChipRow(
            isPendingPullRequestFacts: branchStatus.map {
                SidebarGitStatusChips.showsPendingPullRequestFacts(branchStatus: $0)
            } ?? false
        ) {
            SidebarShortcutHint(LocalActionSpec.previewPaneShortcutDisplay)
            if let branchStatus,
                SidebarGitStatusChips.hasContent(branchStatus: branchStatus)
            {
                SidebarGitStatusChips(branchStatus: branchStatus, octiconLoader: octiconLoader)
            }
            if isDrawerPane {
                SidebarChip(
                    icon: .system(.rectangleBottomhalfFilled),
                    octiconLoader: octiconLoader,
                    text: nil,
                    style: .neutral
                )
            }
            SidebarChip(
                icon: .system(.clock),
                octiconLoader: octiconLoader,
                text: recencyText,
                style: recencyChipStyle
            )
            if isActive {
                SidebarChip(
                    icon: .system(.playCircleFill),
                    octiconLoader: octiconLoader,
                    text: nil,
                    style: .accent(.accentColor)
                )
            }
        }
    }

    private var recencyChipStyle: SidebarChip.Style {
        switch recencyTier {
        case .strongBlue: .accent(AppStyles.Shell.Sidebar.chipInfoColor)
        case .mediumBlue: .accent(AppStyles.Shell.Sidebar.recencyMediumBlue)
        case .mutedBlue: .accent(AppStyles.Shell.Sidebar.recencyMutedBlue)
        case .faintBlue: .accent(AppStyles.Shell.Sidebar.recencyFaintBlue)
        case .grey: .neutral
        }
    }
}

struct RepoExplorerUnassociatedPaneRow: View {
    let primaryText: String
    let secondaryLine: RepoExplorerPaneSecondaryLine?
    let recencyText: String
    let recencyTier: RepoExplorerPaneRecencyTier
    let isActive: Bool
    let isDrawerPane: Bool
    let octiconLoader: OcticonLoader
    var keyboardPresentation = RepoExplorerRowKeyboardPresentation.inactive
    let onFocus: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onFocus) {
            SidebarRowShell(isSelected: keyboardPresentation.isSelected, isHovering: isHovering) {
                RepoExplorerPaneRowContent(
                    primaryText: primaryText,
                    secondaryLine: secondaryLine,
                    branchContextText: nil,
                    branchStatus: nil,
                    recencyText: recencyText,
                    recencyTier: recencyTier,
                    isActive: isActive,
                    isDrawerPane: isDrawerPane,
                    octiconLoader: octiconLoader,
                    shortcutDisplay: keyboardPresentation.shortcutDisplay
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            [primaryText, secondaryLine?.text, isDrawerPane ? "Drawer" : nil, recencyText, isActive ? "Active" : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}
