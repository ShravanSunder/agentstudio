import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

@MainActor
struct RepoExplorerVisibilityButton: View {
    let octiconLoader: OcticonLoader
    let isFavoritesOnly: Bool
    let commandPresentation: RepoExplorerPresentedCommand
    let onToggle: () -> Void

    private var label: String {
        isFavoritesOnly ? "Show All Repos" : "Show Favorite Repos"
    }

    var body: some View {
        let commandSpec = commandPresentation.commandSpec
        SidebarToolbarActionButton(
            label: label,
            accessibilityIdentifier: "repoSidebarVisibilityButton",
            tooltipValue: commandSpec.controlTooltipRenderValue(
                textOverride: label
            ),
            icon: {
                commandSpec.icon.swiftUIImage(
                    loader: octiconLoader,
                    size: AppStyles.General.Icon.compact
                )
            },
            isActive: isFavoritesOnly,
            action: onToggle
        )
        .disabled(!commandPresentation.isEnabled)
    }
}
