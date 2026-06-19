import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct UIActionPresentationTests {
    @Test
    func detachDrawerPaneCommandDefinition_hasStablePresentation() {
        let definition = CommandDispatcher.shared.definition(for: .detachDrawerPane)

        #expect(definition.label == "Detach Drawer Pane")
        #expect(definition.helpText == "Promote the selected drawer pane into the main layout")
        #expect(definition.icon == .system(.rectanglePortraitAndArrowRight))
    }

    @Test
    func controlToolTip_withShortcutAndNoOverride_usesLabelAndShortcut() {
        let toolTip = AppCommand.openPaneLocationInEditorMenu.definition.controlToolTip

        #expect(toolTip == "Open In Menu (⌘⌥O)")
    }

    @Test
    func controlToolTip_withoutShortcutAndNoOverride_usesHelpText() {
        let definition = CommandSpec(
            command: .renameArrangement,
            label: "Rename Arrangement",
            icon: .system(.pencil),
            helpText: "Rename the current arrangement"
        )

        #expect(definition.controlToolTip == "Rename the current arrangement")
    }

    @Test
    func controlToolTip_withOverrideAndShortcut_usesOverrideAndShortcut() {
        let toolTip = AppCommand.openPaneLocationInEditorMenu.definition.controlToolTip(
            textOverride: "Open in Editor"
        )

        #expect(toolTip == "Open in Editor (⌘⌥O)")
    }

    @Test
    func controlToolTip_withOverrideAndNoShortcut_usesOverrideOnly() {
        let definition = CommandSpec(
            command: .renameArrangement,
            label: "Rename Arrangement",
            icon: .system(.pencil),
            helpText: "Rename the current arrangement"
        )

        let toolTip = definition.controlToolTip(textOverride: "Rename")

        #expect(toolTip == "Rename")
    }

    @Test
    func controlToolTip_includeShortcutFalse_suppressesShortcut() {
        let toolTip = AppCommand.openPaneLocationInEditorMenu.definition.controlToolTip(
            textOverride: "Open in Editor",
            includeShortcut: false
        )

        #expect(toolTip == "Open in Editor")
    }

    @Test
    func controlToolTip_withShortcutOverride_usesOverrideShortcut() {
        let toolTip = AppCommand.toggleInboxNotificationSort.definition.controlToolTip(
            textOverride: "Sort inbox",
            shortcutTextOverride: "⌥S"
        )

        #expect(toolTip == "Sort inbox (⌥S)")
    }

    @Test
    func actionSpecControlToolTip_withOverrideAndShortcut_usesCompactText() {
        let toolTip = LocalActionSpec.groupInboxNotifications.actionSpec.controlToolTip(
            textOverride: "Group",
            shortcutText: "⌥G"
        )

        #expect(toolTip == "Group (⌥G)")
    }

    @Test
    func drawerChooserToolTip_usesOverrideWithShortcut() {
        let toolTip = AppCommand.openPaneLocationInEditorMenu.definition.controlToolTip(
            textOverride: "Open in Editor"
        )

        #expect(toolTip == "Open in Editor (⌘⌥O)")
    }

    @Test
    func drawerFinderToolTip_usesOverrideWithShortcut() {
        let toolTip = AppCommand.openPaneLocationInFinder.definition.controlToolTip(
            textOverride: "Open in Finder"
        )

        #expect(toolTip == "Open in Finder (⌘⇧O)")
    }

    @Test
    func paneInboxToolTip_usesOverrideWithShortcut() {
        let toolTip = AppCommand.showPaneInboxNotifications.definition.controlToolTip(
            textOverride: "Open pane inbox"
        )

        #expect(toolTip == "Open pane inbox (⌘⇧U)")
    }

    @Test
    func actionSpec_preservesTypedCommandIcons() {
        #expect(AppCommand.watchFolder.definition.icon == .system(.folderFillBadgePlus))
        #expect(AppCommand.watchFolder.definition.actionSpec.icon == .system(.folderFillBadgePlus))
    }

    @Test
    func refreshAndReloadUseClockwiseArrow() {
        #expect(LocalActionSpec.refreshWorktrees.actionSpec.icon == .system(.arrowClockwise))
        #expect(LocalActionSpec.browserReload.actionSpec.icon == .system(.arrowClockwise))
    }
}
