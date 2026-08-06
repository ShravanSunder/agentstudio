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
    let label: String
    let onFocus: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onFocus) {
            SidebarRowShell(isHovering: isHovering) {
                HStack(spacing: AppStyles.General.Spacing.tight) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

                    Text(label)
                        .font(.system(size: AppStyles.General.Typography.textBase))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
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
