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
    let pullRequestCount: Int?
    let octiconLoader: OcticonLoader
    let onFocus: () -> Void

    @State private var isHovering = false

    static func normalizedPullRequestCount(_ pullRequestCount: Int?) -> Int? {
        guard let pullRequestCount, pullRequestCount > 0 else { return nil }
        return pullRequestCount
    }

    var body: some View {
        Button(action: onFocus) {
            SidebarRowShell(isHovering: isHovering) {
                VStack(alignment: .sidebarTextColumn, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
                    HStack(spacing: AppStyles.Shell.Sidebar.iconTextSpacing) {
                        Image(systemName: "square.split.2x1")
                            .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                            .frame(
                                width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth,
                                alignment: .leading
                            )
                        Text(row.primaryText)
                            .font(.system(size: AppStyles.General.Typography.textBase, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sidebarIconLineTextColumnGuide()
                    SidebarMetadataLine(text: row.secondaryText)
                    chipRow
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            [
                row.primaryText,
                row.secondaryText,
                Self.normalizedPullRequestCount(pullRequestCount).map { "\($0) pull requests" },
                row.recencyText,
                row.isActive ? "Active" : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    @ViewBuilder
    private var chipRow: some View {
        let normalizedPullRequestCount = Self.normalizedPullRequestCount(pullRequestCount)
        HStack(spacing: AppStyles.Shell.Sidebar.chipRowSpacing) {
            if let normalizedPullRequestCount {
                SidebarChip(
                    icon: .octicon("octicon-git-pull-request"),
                    octiconLoader: octiconLoader,
                    text: "\(normalizedPullRequestCount)",
                    style: .accent(.accentColor)
                )
            }
            SidebarChip(
                icon: .system(.clock),
                octiconLoader: octiconLoader,
                text: row.recencyText,
                style: .neutral
            )
            if row.isActive {
                SidebarChip(
                    icon: .system(.circleFill),
                    octiconLoader: octiconLoader,
                    text: "active",
                    style: .accent(.accentColor)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarTextColumnGuide()
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
