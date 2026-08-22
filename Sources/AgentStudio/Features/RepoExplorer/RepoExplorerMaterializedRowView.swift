import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import SwiftUI

struct RepoExplorerMaterializedRowView: View {
    let row: RepoExplorerMaterializedRow
    let octiconLoader: OcticonLoader

    var body: some View {
        content
            .padding(.leading, row.layout.metrics.leadingInset)
            .padding(.trailing, row.layout.metrics.trailingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch row.presentation {
        case .sectionHeader(let kind, let isFirstRow):
            SectionSubheadingLabel(kind.title)
                .padding(.leading, AppStyles.Shell.Sidebar.listRowLeadingInset)
                .padding(.trailing, AppStyles.Components.SectionSubheading.horizontalPadding)
                .padding(.top, isFirstRow ? 0 : AppStyles.Components.SectionSubheading.topPadding)
                .padding(.bottom, AppStyles.Components.SectionSubheading.bottomPadding)
                .accessibilityAddTraits(.isHeader)
        case .loadingSectionHeader(_, let state):
            RepoExplorerLoadingSectionHeaderRow(state: state)
                .padding(.top, AppStyles.General.Spacing.standard)
                .padding(.bottom, AppStyles.General.Spacing.tight)
        case .loadingRepository(_, _, let name, let isStatusUnavailable):
            RepoExplorerLoadingRepoRow(
                repoName: name,
                isStatusUnavailable: isStatusUnavailable
            )
            .allowsHitTesting(false)
        case .groupHeader(let group):
            SidebarRepoGroupHeader(
                isCollapsed: !group.isExpanded,
                octiconLoader: octiconLoader,
                icon: group.icon,
                repoTitle: group.title,
                organizationName: group.organizationName,
                onToggle: {}
            )
            .allowsHitTesting(false)
        case .worktree(let worktree):
            SidebarRowShell(isHovering: false) {
                RepoExplorerWorktreeRowContent(
                    octiconLoader: octiconLoader,
                    checkoutTitle: worktree.checkoutTitle,
                    branchName: worktree.branchName,
                    placementText: worktree.placementText,
                    checkoutIconKind: worktree.isMainCheckout ? .mainCheckout : .gitWorktree,
                    iconColor: Color(
                        nsColor: NSColor(hex: worktree.checkoutColorHex)
                            ?? AppStyles.General.Accent.primaryNSColor
                    ),
                    branchStatus: worktree.branchStatus,
                    showsFavoriteControl: false
                )
            }
        case .associatedPane(let pane):
            SidebarRowShell(isHovering: false) {
                RepoExplorerPaneRowContent(
                    primaryText: pane.primaryText,
                    secondaryLine: pane.secondaryLine,
                    branchContextText: pane.branchContextText,
                    branchStatus: pane.branchStatus,
                    recencyText: pane.recencyText,
                    recencyTier: pane.recencyTier,
                    isActive: pane.isActive,
                    isDrawerPane: pane.isDrawerPane,
                    octiconLoader: octiconLoader
                )
            }
        case .unassociatedPane(let pane):
            SidebarRowShell(isHovering: false) {
                RepoExplorerPaneRowContent(
                    primaryText: pane.primaryText,
                    secondaryLine: pane.secondaryLine,
                    branchContextText: nil,
                    branchStatus: nil,
                    recencyText: pane.recencyText,
                    recencyTier: pane.recencyTier,
                    isActive: pane.isActive,
                    isDrawerPane: pane.isDrawerPane,
                    octiconLoader: octiconLoader
                )
            }
        case .topologyFault(let fault):
            RepoExplorerTopologyFaultRow(fault: fault)
        case .unresolved:
            Text("Repository data unavailable")
                .font(.system(size: AppStyles.General.Typography.textSm))
                .foregroundStyle(.secondary)
        }
    }

    static func accessibilityLabel(for row: RepoExplorerMaterializedRow) -> String {
        switch row.presentation {
        case .sectionHeader(let kind, _):
            kind.title
        case .loadingSectionHeader(_, let state):
            switch state {
            case .scanning: "Scanning"
            case .statusUnavailable: "Status unavailable"
            case .mixed: "Scanning; some status unavailable"
            }
        case .loadingRepository(_, _, let name, let isStatusUnavailable):
            isStatusUnavailable ? "\(name), status unavailable" : name
        case .groupHeader(let group):
            [group.title, group.organizationName].compactMap { $0 }.joined(separator: ", ")
        case .worktree(let worktree):
            [worktree.checkoutTitle, worktree.branchName, worktree.placementText]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        case .associatedPane(let pane):
            [
                pane.primaryText,
                pane.secondaryText,
                pane.branchContextText,
                pane.isDrawerPane ? "Drawer" : nil,
                pane.recencyText,
                pane.isActive ? "Active" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        case .unassociatedPane(let pane):
            [
                pane.primaryText,
                pane.secondaryLine?.text,
                pane.isDrawerPane ? "Drawer" : nil,
                pane.recencyText,
                pane.isActive ? "Active" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        case .topologyFault, .unresolved:
            "Repository data unavailable"
        }
    }
}
