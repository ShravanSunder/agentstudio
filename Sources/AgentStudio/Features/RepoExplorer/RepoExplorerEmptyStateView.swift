import SwiftUI

@MainActor
struct RepoExplorerEmptyStateView: View {
    let emptyState: RepoExplorerEmptyState

    private var systemImage: String {
        switch emptyState {
        case .content:
            "folder"
        case .searchNoResults:
            "magnifyingglass"
        case .favoritesOnlyEmpty:
            "bookmark"
        }
    }

    private var title: String {
        switch emptyState {
        case .content:
            ""
        case .searchNoResults:
            "No results"
        case .favoritesOnlyEmpty:
            "No favorites"
        }
    }

    var body: some View {
        VStack(spacing: AppStyles.Shell.Sidebar.EmptyState.contentSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: AppStyles.General.Typography.text2xl))
                .foregroundStyle(.secondary)
                .opacity(AppStyles.Shell.Sidebar.EmptyState.iconOpacity)

            Text(title)
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.animation(.easeOut(duration: AppStyles.Shell.Sidebar.EmptyState.transitionDuration)))
    }
}
