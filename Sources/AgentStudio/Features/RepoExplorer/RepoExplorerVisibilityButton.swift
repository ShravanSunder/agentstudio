import SwiftUI

@MainActor
struct RepoExplorerVisibilityButton: View {
    let isFavoritesOnly: Bool
    let onToggle: () -> Void

    private var commandSpec: AppCommandSpec {
        AppCommand.setRepoSidebarVisibilityMode.definition
    }

    private var label: String {
        isFavoritesOnly ? "Show All Repos" : "Show Favorite Repos"
    }

    var body: some View {
        let commandSpec = commandSpec
        SidebarToolbarActionButton(
            label: label,
            accessibilityIdentifier: "repoSidebarVisibilityButton",
            tooltipValue: commandSpec.controlTooltipRenderValue(
                textOverride: label
            ),
            icon: commandSpec.icon,
            isActive: isFavoritesOnly,
            action: onToggle
        )
    }
}
