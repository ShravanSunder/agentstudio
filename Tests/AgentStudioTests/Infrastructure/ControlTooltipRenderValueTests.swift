import Testing

@testable import AgentStudio

@Suite
struct ControlTooltipRenderValueTests {
    @Test("stores resolved tooltip text and optional shortcut display")
    func storesResolvedTooltipTextAndShortcutDisplay() {
        let shortcut = ShortcutDisplayText(value: "⌥G")
        let renderValue = ControlTooltipRenderValue(
            text: "Group (⌥G)",
            shortcutDisplayText: shortcut
        )

        #expect(renderValue.text == "Group (⌥G)")
        #expect(renderValue.shortcutDisplayText == shortcut)
    }

    @Test("shortcut display text preserves already-projected glyphs")
    func shortcutDisplayTextPreservesProjectedGlyphs() {
        let shortcut = ShortcutDisplayText(value: "⌘⇧U")

        #expect(shortcut.value == "⌘⇧U")
    }
}
