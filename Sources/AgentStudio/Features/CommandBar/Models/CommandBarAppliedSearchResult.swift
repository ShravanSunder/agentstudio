import AgentStudioCore

/// One accepted service answer and the rows from its exact document generation.
struct CommandBarAppliedSearchResult {
    let sequence: SearchRequestSequence
    let generation: SearchDocumentGeneration
    let itemSnapshot: CommandBarItemSnapshot
    let groups: [CommandBarItemGroup]
    let displayedItems: [CommandBarItem]
    let titleMatchesByItemId: [String: Range<Int>]
    let dimmedItemIds: Set<String>
    let canOpenWorktreeInCurrentTab: Bool
    let focusedPane: WorkspaceFocusedPane?
    let commandContext: CommandContext
}

struct CommandBarPreparedSearch {
    let documentSet: SearchDocumentSet
    let itemSnapshot: CommandBarItemSnapshot
    let rowsById: [SearchItemId: CommandBarItem]
    let canOpenWorktreeInCurrentTab: Bool
    let focusedPane: WorkspaceFocusedPane?
    let commandContext: CommandContext
}

struct CommandBarPublicationIdentity: Equatable {
    let sequence: SearchRequestSequence
    let generation: SearchDocumentGeneration
}
