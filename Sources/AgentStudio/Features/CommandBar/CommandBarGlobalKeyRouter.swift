import Foundation

enum CommandBarGlobalKeyRouter {
    static func reservedPrefix(for trigger: ShortcutTrigger) -> String?? {
        switch trigger {
        case AppShortcut.showCommandBarEverything.trigger:
            return .some(nil)
        case AppShortcut.showCommandBarCommands.trigger:
            return .some(">")
        case AppShortcut.showCommandBarPanes.trigger:
            return .some("$")
        default:
            return nil
        }
    }

    static func isDismissTrigger(_ trigger: ShortcutTrigger) -> Bool {
        trigger.key == .escape && trigger.modifiers.isEmpty
    }
}
