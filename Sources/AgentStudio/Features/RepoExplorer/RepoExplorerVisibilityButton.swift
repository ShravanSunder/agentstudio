import SwiftUI

struct RepoExplorerVisibilityButton: View {
    let isFavoritesOnly: Bool
    let onToggle: () -> Void

    private var actionSpec: ActionSpec {
        LocalActionSpec.toggleRepoSidebarFavoritesOnly(isFavoritesOnly: isFavoritesOnly).actionSpec
    }

    var body: some View {
        let actionSpec = actionSpec
        Button(action: onToggle) {
            actionSpec.icon.swiftUIImage(size: AppStyles.General.Icon.compact)
                .frame(
                    width: AppStyles.General.Button.compact,
                    height: AppStyles.General.Button.compact
                )
                .foregroundStyle(Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(actionSpec.label)
        .accessibilityIdentifier("repoSidebarVisibilityButton")
        .controlHelp(
            actionSpec.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "toggleRepoSidebarFavoritesOnly"),
                textOverride: actionSpec.label
            )
        )
    }
}
