import SwiftUI

// MARK: - CommandBarResultsList

/// Grouped scrollable list with results. Shows group headers per section.
struct CommandBarResultsList: View {
    let groups: [CommandBarItemGroup]
    let selectedIndex: Int
    let searchQuery: String
    let dimmedItemIds: Set<String>
    let onSelect: (CommandBarItem) -> Void

    init(
        groups: [CommandBarItemGroup],
        selectedIndex: Int,
        searchQuery: String = "",
        dimmedItemIds: Set<String> = [],
        onSelect: @escaping (CommandBarItem) -> Void
    ) {
        self.groups = groups
        self.selectedIndex = selectedIndex
        self.searchQuery = searchQuery
        self.dimmedItemIds = dimmedItemIds
        self.onSelect = onSelect
    }

    var body: some View {
        if groups.isEmpty || groups.allSatisfy({ $0.items.isEmpty }) {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        let flatItems = flattenedItems()
                        ForEach(Array(flatItems.enumerated()), id: \.element.id) { _, entry in
                            switch entry {
                            case .header(let name):
                                CommandBarGroupHeader(name: name)
                            case .item(let item, let flatIndex):
                                CommandBarResultRow(
                                    item: item,
                                    isSelected: flatIndex == selectedIndex,
                                    searchQuery: searchQuery,
                                    isDimmed: dimmedItemIds.contains(item.id)
                                )
                                .id(item.id)
                                .onTapGesture {
                                    if !dimmedItemIds.contains(item.id) {
                                        onSelect(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: selectedIndex) { _, newIndex in
                    if let itemId = itemId(at: newIndex) {
                        proxy.scrollTo(itemId, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No results")
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .foregroundStyle(.primary.opacity(0.5))
            Text("Try a different search term")
                .font(.system(size: AppStyle.textXs))
                .foregroundStyle(.primary.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private func flattenedItems() -> [FlatEntry] {
        var entries: [FlatEntry] = []
        var itemIndex = 0

        for group in groups {
            guard !group.items.isEmpty else { continue }
            entries.append(.header(group.name))
            for item in group.items {
                entries.append(.item(item, flatIndex: itemIndex))
                itemIndex += 1
            }
        }
        return entries
    }

    private func itemId(at flatIndex: Int) -> String? {
        var current = 0
        for group in groups {
            for item in group.items {
                if current == flatIndex { return item.id }
                current += 1
            }
        }
        return nil
    }
}

// MARK: - FlatEntry

private enum FlatEntry: Identifiable {
    case header(String)
    case item(CommandBarItem, flatIndex: Int)

    var id: String {
        switch self {
        case .header(let name): return "header-\(name)"
        case .item(let item, _): return item.id
        }
    }
}
