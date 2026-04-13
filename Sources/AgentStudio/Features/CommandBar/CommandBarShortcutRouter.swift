import Foundation

enum CommandBarShortcutRoute {
    case dismiss
    case showPrefix(String?)
    case executeRow(CommandBarItem)
    case executeSelected(EnterModifier)
    case unhandled
}

enum CommandBarShortcutRouter {
    static func route(
        trigger: ShortcutTrigger,
        selectedItem: CommandBarItem?,
        displayedItems: [CommandBarItem]
    ) -> CommandBarShortcutRoute {
        if CommandBarGlobalKeyRouter.isDismissTrigger(trigger) {
            return .dismiss
        }

        if let reservedPrefix = CommandBarGlobalKeyRouter.reservedPrefix(for: trigger) {
            return .showPrefix(reservedPrefix)
        }

        if let item = CommandBarRowShortcutResolver.selectedItem(
            for: trigger,
            selectedItem: selectedItem,
            displayedItems: displayedItems
        ) {
            return .executeRow(item)
        }

        if let modifier = enterModifier(for: trigger) {
            return .executeSelected(modifier)
        }

        return .unhandled
    }

    static func enterModifier(for trigger: ShortcutTrigger) -> EnterModifier? {
        guard trigger.key == .enter else { return nil }
        if trigger.modifiers.contains(.command) {
            return .command
        }
        if trigger.modifiers.contains(.option) {
            return .option
        }
        return nil
    }
}
