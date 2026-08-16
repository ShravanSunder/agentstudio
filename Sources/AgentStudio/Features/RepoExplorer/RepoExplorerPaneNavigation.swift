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
                VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
                    HStack(spacing: AppStyles.General.Spacing.tight) {
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
                        if row.isActive {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(
                                    width: AppStyles.Shell.Sidebar.activePaneMarkerSize,
                                    height: AppStyles.Shell.Sidebar.activePaneMarkerSize
                                )
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SidebarMetadataLine(iconSystemName: "terminal", text: row.secondaryText)
                    if row.recencyText != nil || row.isActive {
                        HStack(spacing: AppStyles.Shell.Sidebar.chipRowSpacing) {
                            if let recencyText = row.recencyText {
                                SidebarChip(
                                    icon: .system(.clock),
                                    octiconLoader: octiconLoader,
                                    text: recencyText,
                                    style: .neutral
                                )
                            }
                            if row.isActive {
                                SidebarChip(
                                    icon: .system(.circleFill),
                                    octiconLoader: octiconLoader,
                                    text: "Active",
                                    style: .accent(.accentColor)
                                )
                            }
                        }
                        .padding(.leading, AppStyles.Shell.Sidebar.statusRowLeadingIndent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            [row.primaryText, row.secondaryText, row.recencyText, row.isActive ? "Active" : nil]
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
