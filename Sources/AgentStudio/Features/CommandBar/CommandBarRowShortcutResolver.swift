import Foundation
import os.log

private let commandBarRowShortcutLogger = Logger(
    subsystem: "com.agentstudio",
    category: "CommandBarRowShortcutResolver"
)

enum CommandBarRowShortcutResolver {
    static func selectedItem(
        for trigger: ShortcutTrigger,
        selectedItem: CommandBarItem?,
        displayedItems: [CommandBarItem]
    ) -> CommandBarItem? {
        let matchingItems = displayedItems.filter { $0.shortcutTrigger == trigger }

        switch matchingItems.count {
        case 0:
            return nil
        case 1:
            return matchingItems[0]
        default:
            commandBarRowShortcutLogger.warning(
                "Duplicate visible command bar shortcut trigger: \(String(describing: trigger), privacy: .public)"
            )
            if let selectedItem, matchingItems.contains(where: { $0.id == selectedItem.id }) {
                return selectedItem
            }
            return matchingItems.first
        }
    }
}
