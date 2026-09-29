import AgentStudioCore

@testable import AgentStudioCommandBar

/// Exercises declared row fields against the production SQLite service.
@MainActor
func searchCommandBarItemIds(_ items: [CommandBarItem], query: String) async -> [String] {
    var groups: [SearchGroup] = []
    var seenGroupIds: Set<String> = []
    for item in items where seenGroupIds.insert(item.group).inserted {
        groups.append(SearchGroup(id: item.group, priority: item.groupPriority))
    }
    let documents = items.compactMap { item -> SearchDocument? in
        guard let itemId = SearchItemId(item.id) else { return nil }
        let kind: SearchKind =
            switch item.kind {
            case .repo: .repo
            case .worktree: .worktree
            case .pane: .pane
            case .tab: .tab
            case .command: .command
            case .other: .other
            }
        return SearchDocument(
            itemId: itemId,
            kind: kind,
            groupId: item.group,
            title: item.title,
            fields: item.searchFields
        )
    }
    let result = await SearchService().search(
        SearchRequest(
            sequence: SearchRequestSequence(1),
            text: query,
            recentItemIds: [],
            documentSet: SearchDocumentSet(
                generation: SearchDocumentGeneration(1),
                groups: groups,
                documents: documents
            )
        )
    )
    return result.groups.flatMap(\.matches).map { $0.itemId.rawValue }
}
