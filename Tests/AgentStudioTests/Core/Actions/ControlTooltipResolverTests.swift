import Testing

@testable import AgentStudio

@Suite
struct ControlTooltipResolverTests {
    @Test("compact display source uses compact copy and shortcut")
    func compactDisplaySourceUsesCompactCopyAndShortcut() {
        let descriptor = CommandDisplayDescriptor(
            provenance: .localAction(rawValue: "groupInboxNotifications"),
            label: "Group Notifications",
            helpText: "Group inbox notifications",
            compactTooltipText: "Group",
            shortcutDisplayText: ShortcutDisplayText(value: "⌥G")
        )

        let renderValue = ControlTooltipResolver.resolve(.display(descriptor))

        #expect(renderValue.text == "Group (⌥G)")
        #expect(renderValue.shortcutDisplayText == ShortcutDisplayText(value: "⌥G"))
    }

    @Test("helpText style uses help copy without manually appending at call site")
    func helpTextStyleUsesHelpCopyWithShortcut() {
        let descriptor = CommandDisplayDescriptor(
            provenance: .appCommand(rawValue: "toggleDrawer"),
            label: "Toggle Drawer",
            helpText: "Show or hide the drawer",
            compactTooltipText: "Drawer",
            shortcutDisplayText: ShortcutDisplayText(value: "⌘J")
        )

        let renderValue = ControlTooltipResolver.resolve(.display(descriptor, style: .helpText))

        #expect(renderValue.text == "Show or hide the drawer (⌘J)")
        #expect(renderValue.shortcutDisplayText == ShortcutDisplayText(value: "⌘J"))
    }

    @Test("label style can suppress shortcut rendering")
    func labelStyleCanSuppressShortcutRendering() {
        let descriptor = CommandDisplayDescriptor(
            provenance: .localShortcut(rawValue: "inbox.toggleSort"),
            label: "Sort Inbox",
            helpText: "Sort inbox notifications",
            compactTooltipText: "Sort inbox",
            shortcutDisplayText: ShortcutDisplayText(value: "⌥S")
        )

        let renderValue = ControlTooltipResolver.resolve(
            .display(descriptor, style: .label(includeShortcut: false))
        )

        #expect(renderValue.text == "Sort Inbox")
        #expect(renderValue.shortcutDisplayText == nil)
    }

    @Test("dynamic data source requires a reason and preserves text")
    func dynamicDataSourceRequiresReasonAndPreservesText() {
        let renderValue = ControlTooltipResolver.resolve(
            .dynamicData(
                .filesystemPath,
                text: "/Users/dev/project",
                shortcut: nil
            )
        )

        #expect(renderValue.text == "/Users/dev/project")
        #expect(renderValue.shortcutDisplayText == nil)
    }

    @Test("dynamic data source composes shortcut into rendered text")
    func dynamicDataSourceComposesShortcutIntoRenderedText() {
        let renderValue = ControlTooltipResolver.resolve(
            .dynamicData(
                .stateReadout,
                text: "Mark pane notifications read",
                shortcut: ShortcutDisplayText(value: "⌥F")
            )
        )

        #expect(renderValue.text == "Mark pane notifications read (⌥F)")
        #expect(renderValue.shortcutDisplayText == ShortcutDisplayText(value: "⌥F"))
    }

    @Test("action spec compatibility adapter derives from typed source")
    func actionSpecCompatibilityAdapterDerivesFromTypedSource() {
        let action = ActionSpec(
            label: "Group Notifications",
            helpText: "Group inbox notifications",
            icon: .system(.squareStack3dUp)
        )

        let source = action.controlTooltipSource(
            provenance: .localAction(rawValue: "groupInboxNotifications"),
            textOverride: "Group",
            shortcutText: ShortcutDisplayText(value: "⌥G")
        )
        let renderValue = ControlTooltipResolver.resolve(source)

        #expect(
            renderValue
                == action.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: "groupInboxNotifications"),
                    textOverride: "Group",
                    shortcutText: ShortcutDisplayText(value: "⌥G")
                ))
        #expect(
            action.controlToolTip(textOverride: "Group", shortcutText: ShortcutDisplayText(value: "⌥G"))
                == renderValue.text)
    }
}
