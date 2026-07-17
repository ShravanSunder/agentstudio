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
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: AppStyles.General.Typography.text2xl))
                .foregroundStyle(.secondary)
                .opacity(0.5)

            Text(title)
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
    }
}
