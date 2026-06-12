import Foundation

struct CommandBarResultSnapshot {
    let itemSnapshot: CommandBarItemSnapshot
    let searchDocument: CommandBarSearchDocument
    let allItems: [CommandBarItem]
    let filteredItems: [CommandBarItem]
    let groups: [CommandBarItemGroup]
    let displayedItems: [CommandBarItem]
    let selectedItem: CommandBarItem?
    let dimmedItemIds: Set<String>
    let footerHints: [FooterHint]
    let canOpenWorktreeInCurrentTab: Bool
    let currentMode: CommandBarAppMode
    let currentContext: WorkspacePaneFocus

    var totalItems: Int {
        displayedItems.count
    }
}
