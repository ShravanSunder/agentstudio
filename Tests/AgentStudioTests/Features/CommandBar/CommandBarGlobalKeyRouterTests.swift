import Testing

@testable import AgentStudio

@Suite
struct CommandBarGlobalKeyRouterTests {
    @Test
    func escapeWithoutModifiersIsDismissTrigger() {
        let trigger = ShortcutTrigger(key: .escape, modifiers: [])

        #expect(CommandBarGlobalKeyRouter.isDismissTrigger(trigger))
    }

    @Test
    func modifiedEscapeIsNotDismissTrigger() {
        let trigger = ShortcutTrigger(key: .escape, modifiers: [.command])

        #expect(!CommandBarGlobalKeyRouter.isDismissTrigger(trigger))
    }

    @Test
    func reservedPaletteTriggersMapToExpectedPrefixes() {
        #expect(
            CommandBarGlobalKeyRouter.reservedPrefix(
                for: AppShortcut.showCommandBarEverything.trigger
            ) == .some(nil)
        )
        #expect(CommandBarGlobalKeyRouter.reservedPrefix(for: AppShortcut.showCommandBarCommands.trigger) == .some(">"))
        #expect(CommandBarGlobalKeyRouter.reservedPrefix(for: AppShortcut.showCommandBarPanes.trigger) == .some("$"))
    }

    @Test
    func nonPaletteTriggerHasNoReservedPrefix() {
        let trigger = ShortcutTrigger(key: .character(.w), modifiers: [.command])

        #expect(CommandBarGlobalKeyRouter.reservedPrefix(for: trigger) == nil)
    }
}
