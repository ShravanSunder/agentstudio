import SwiftUI

struct RepoExplorerVisibilityButton: View {
    let isFavoritesOnly: Bool
    let onToggle: () -> Void

    private var actionSpec: ActionSpec {
        LocalActionSpec.toggleRepoSidebarFavoritesOnly(isFavoritesOnly: isFavoritesOnly).actionSpec
    }

    var body: some View {
        let actionSpec = actionSpec
        SidebarToolbarActionButton(
            label: actionSpec.label,
            accessibilityIdentifier: "repoSidebarVisibilityButton",
            tooltipValue: actionSpec.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "toggleRepoSidebarFavoritesOnly"),
                textOverride: actionSpec.label
            ),
            icon: actionSpec.icon,
            isActive: isFavoritesOnly,
            action: onToggle
        )
    }
}
