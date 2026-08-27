import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

package struct RepoExplorerPanePresentation: Identifiable {
    let destination: RepoExplorerPaneDestination
    let label: String

    package var id: UUID { destination.paneId }
}

struct RepoExplorerPaneRow: View {
    let row: RepoExplorerProjectedPaneRow
    let octiconLoader: OcticonLoader
    let onFocus: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onFocus) {
            SidebarRowShell(isHovering: isHovering) {
                RepoExplorerPaneRowContent(
                    primaryText: row.primaryText,
                    secondaryLine: row.secondaryLine,
                    branchContextText: row.branchContextText,
                    branchStatus: row.branchStatus,
                    recencyText: row.recencyText,
                    recencyTier: row.recencyTier,
                    isActive: row.isActive,
                    isDrawerPane: row.isDrawerPane,
                    octiconLoader: octiconLoader
                )
            }
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .sidebarTextColumn, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.Shell.Sidebar.groupIconTitleSpacing) {
                AppEntityIcon.pane.swiftUIImage(
                    loader: octiconLoader,
                    size: AppStyles.Shell.Sidebar.rowIdentityIconSize
                )
                .frame(
                    width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth,
                    alignment: .trailing
                )
                Text(primaryText)
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarIconLineTextColumnGuide()
            if let secondaryLine {
                SidebarMetadataLine(
                    icon: .systemName(secondaryLine.iconSystemName),
                    text: secondaryLine.text
                )
                .saturation(secondaryLine.isTerminalOutput ? 0 : 1)
            }
            if let branchContextText {
                SidebarMetadataLine(
                    icon: .octicon(name: "octicon-git-branch", loader: octiconLoader),
                    text: branchContextText
                )
            }
            chipRow
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.chipRowSpacing) {
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
                    icon: .system(.circleFill),
                    octiconLoader: octiconLoader,
                    text: "Active",
                    style: .accent(.accentColor)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarChipRowTextColumnGuide()
        .sidebarPendingPullRequestIndicator(
            isVisible: branchStatus.map {
                SidebarGitStatusChips.showsPendingPullRequestFacts(branchStatus: $0)
            } ?? false
        )
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
    let onFocus: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onFocus) {
            SidebarRowShell(isHovering: isHovering) {
                RepoExplorerPaneRowContent(
                    primaryText: primaryText,
                    secondaryLine: secondaryLine,
                    branchContextText: nil,
                    branchStatus: nil,
                    recencyText: recencyText,
                    recencyTier: recencyTier,
                    isActive: isActive,
                    isDrawerPane: isDrawerPane,
                    octiconLoader: octiconLoader
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

struct RepoExplorerPaneDestinationMenuContent: View {
    let presentations: [RepoExplorerPanePresentation]
    let onFocusPane: (UUID) -> Void

    var body: some View {
        ForEach(presentations) { presentation in
            Button(presentation.label) {
                onFocusPane(presentation.destination.paneId)
            }
        }
    }
}

struct RepoExplorerRepoHeaderContextMenuModifier: ViewModifier {
    let repo: RepoPresentationItem?
    let panePresentations: [RepoExplorerPanePresentation]
    let onFocusPane: (UUID) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if let repo {
            content.contextMenu {
                if !panePresentations.isEmpty {
                    Menu(LocalActionSpec.goToPane.actionSpec.label) {
                        RepoExplorerPaneDestinationMenuContent(
                            presentations: panePresentations,
                            onFocusPane: onFocusPane
                        )
                    }
                }

                Button(LocalActionSpec.revealInFinder.actionSpec.label) {
                    PathActions.revealInFinder(repo.repoPath)
                }

                Button(LocalActionSpec.copyPath.actionSpec.label) {
                    PathActions.copyPath(repo.repoPath)
                }
            }
        } else {
            content
        }
    }
}
