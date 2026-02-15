import SwiftUI

/// New tab page showing a search bar, favorites grid, and recent sites.
/// Displayed when the webview pane is on about:blank.
struct WebviewNewTabView: View {
    var onNavigate: (URL) -> Void

    @State private var searchQuery: String = ""

    private var history: URLHistoryService { .shared }

    private var hasQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fuzzyResults: [SearchResult] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return history.allSearchable().compactMap { entry in
            // Match against title and URL, take best score
            let titleMatch = CommandBarSearch.fuzzyMatch(pattern: query, in: entry.title)
            let urlMatch = CommandBarSearch.fuzzyMatch(pattern: query, in: entry.url.absoluteString)

            let bestScore: Double
            if let t = titleMatch, let u = urlMatch {
                bestScore = min(t.score, u.score)
            } else if let t = titleMatch {
                bestScore = t.score
            } else if let u = urlMatch {
                bestScore = u.score
            } else {
                return nil
            }

            guard bestScore < CommandBarSearch.defaultThreshold else { return nil }
            return SearchResult(entry: entry, score: bestScore)
        }
        .sorted { $0.score < $1.score }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if hasQuery {
                        searchResults
                    } else {
                        favoritesSection
                        recentSection
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SelectAllTextField(
                placeholder: "Search favorites and history\u{2026}",
                text: $searchQuery,
                onSubmit: {
                    // Navigate to top result on Enter
                    if let first = fuzzyResults.first {
                        onNavigate(first.entry.url)
                    }
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Favorites

    @ViewBuilder
    private var favoritesSection: some View {
        if !history.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Favorites")

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 130))],
                    spacing: 12
                ) {
                    ForEach(history.favorites) { entry in
                        FavoriteCard(entry: entry) {
                            onNavigate(entry.url)
                        } onRemove: {
                            history.removeFavorite(url: entry.url)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Sites

    @ViewBuilder
    private var recentSection: some View {
        let recent = history.recentSites()
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Recent")

                ForEach(recent) { entry in
                    RecentSiteRow(entry: entry) {
                        onNavigate(entry.url)
                    }
                }
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResults: some View {
        let results = fuzzyResults
        if results.isEmpty {
            Text("No results")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 32)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(results) { result in
                    RecentSiteRow(entry: result.entry) {
                        onNavigate(result.entry.url)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Search Result

private struct SearchResult: Identifiable {
    let entry: URLHistoryEntry
    let score: Double
    var id: String { entry.id }
}

// MARK: - Favorite Card

private struct FavoriteCard: View {
    let entry: URLHistoryEntry
    var onTap: () -> Void
    var onRemove: () -> Void

    @State private var isHovered = false

    private var initial: String {
        String(entry.title.prefix(1)).uppercased()
    }

    private var initialColor: Color {
        let hash = entry.url.absoluteString.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.7)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(initialColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Text(initial)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(initialColor)
                }

                Text(entry.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }
            .frame(width: 100, height: 80)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recent Site Row

private struct RecentSiteRow: View {
    let entry: URLHistoryEntry
    var onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)

                Text(entry.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(entry.url.host() ?? entry.url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
