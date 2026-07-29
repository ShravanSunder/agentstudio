import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioInboxNotification

@Suite("InboxSidebarToolbarPresentation")
struct InboxSidebarToolbarPresentationTests {
    @Test("sidebar command presentation includes exact contextual inline controls")
    @MainActor
    func sidebarCommandPresentationIncludesExactContextualInlineControls() {
        let presentation = InboxSidebarCommandPresentation(commandContext: .empty)

        #expect(presentation.sort?.command == .toggleInboxNotificationSort)
        #expect(presentation.rowStateFilter?.command == .setInboxRowStateFilter)
        #expect(presentation.contentMode?.command == .setInboxContentMode)
        #expect(presentation.clearRead?.command == .clearReadInboxNotifications)
        #expect(presentation.clearAll?.command == .clearAllInboxNotifications)
        #expect(
            presentation.groupingOptions.map(\.grouping) == [
                .byTab,
                .byRepo,
                .byPane,
                .none,
            ])
        #expect(
            presentation.groupingOptions.map(\.spec.command) == [
                .setInboxGroupingTab,
                .setInboxGroupingRepo,
                .setInboxGroupingPane,
                .setInboxGroupingNone,
            ])
    }

    @Test("sidebar command capability remains separate from presentation")
    @MainActor
    func sidebarCommandCapabilityRemainsSeparateFromPresentation() {
        let dispatcher = InboxSidebarCommandDispatcherProbe(
            deniedCommands: [.clearAllInboxNotifications]
        )
        let presentation = InboxSidebarCommandPresentation(commandContext: .empty)
        let capability = InboxSidebarCommandCapability(dispatcher: dispatcher)

        #expect(presentation.clearAll != nil)
        #expect(capability.canDispatch(.clearReadInboxNotifications))
        #expect(!capability.canDispatch(.clearAllInboxNotifications))
    }

    @Test("delete command rows source presentation from command specs")
    @MainActor
    func deleteCommandRowsSourcePresentationFromCommandSpecs() throws {
        let presentation = InboxSidebarCommandPresentation(commandContext: .empty)
        let clearRead = try #require(presentation.clearRead)
        let clearAll = try #require(presentation.clearAll)

        #expect(clearRead.label == AppCommand.clearReadInboxNotifications.definition.label)
        #expect(clearRead.icon == AppCommand.clearReadInboxNotifications.definition.icon)
        #expect(clearRead.helpText == AppCommand.clearReadInboxNotifications.definition.helpText)
        #expect(clearAll.label == AppCommand.clearAllInboxNotifications.definition.label)
        #expect(clearAll.icon == AppCommand.clearAllInboxNotifications.definition.icon)
        #expect(clearAll.helpText == AppCommand.clearAllInboxNotifications.definition.helpText)
    }

    @Test("inbox header controls use distinct symbols and grouped row indentation")
    @MainActor
    func inboxHeaderControlsUseDistinctSymbolsAndGroupedRowIndentation() {
        let sortIcon = AppCommand.toggleInboxNotificationSort.definition.icon
        let rowStateAction = AppCommand.setInboxRowStateFilter.definition
        let contentModeAction = AppCommand.setInboxContentMode.definition

        #expect(sortIcon == .system(.arrowUpArrowDown))
        #expect(rowStateAction.icon == .system(.envelopeBadge))
        #expect(InboxSidebarHeader.rowStateButtonLabel(rowStateFilter: .unreadOnly) == "Show All Inbox Notifications")
        #expect(InboxSidebarHeader.rowStateButtonLabel(rowStateFilter: .all) == "Show Unread Only")
        #expect(contentModeAction.icon == .system(.dotCircleViewfinder))
        #expect(InboxSidebarHeader.contentModeButtonLabel(contentMode: .all) == "Show Attention Notifications")
        #expect(InboxSidebarHeader.contentModeButtonLabel(contentMode: .rollUpAlerts) == "Show All Notifications")
        #expect(LocalActionSpec.groupInboxNotifications.actionSpec.icon == .system(.squareStack3dUp))
        #expect(LocalActionSpec.deleteInboxNotifications.actionSpec.icon == .system(.deleteLeft))
        #expect(InboxSidebarHeader.groupIconName == "square.stack.3d.up")
        #expect(InboxSidebarHeader.filterIconName == "line.3.horizontal.decrease.circle")
        #expect(
            InboxSidebarToolbarTooltipTarget.allCases == [
                .delete,
                .sort,
                .rowState,
                .contentMode,
                .grouping,
            ])
        #expect(
            InboxSidebarHeader.toolbarTooltipText(
                for: .sort,
                rowStateFilter: .unreadOnly,
                contentMode: .rollUpAlerts
            ) == "Sort inbox (\(InboxSidebarKeyboardHint.toggleSort))"
        )
        #expect(
            InboxSidebarHeader.toolbarTooltipText(
                for: .rowState,
                rowStateFilter: .unreadOnly,
                contentMode: .rollUpAlerts
            ) == "Show all"
        )
        #expect(
            InboxSidebarHeader.toolbarTooltipText(
                for: .contentMode,
                rowStateFilter: .unreadOnly,
                contentMode: .rollUpAlerts
            ) == "Show all notifications"
        )
        #expect(
            InboxSidebarHeader.toolbarTooltipText(
                for: .grouping,
                rowStateFilter: .unreadOnly,
                contentMode: .rollUpAlerts
            ) == "Group (\(InboxSidebarKeyboardHint.toggleGroupingMenu))"
        )
        #expect(
            InboxSidebarHeader.toolbarTooltipText(
                for: .delete,
                rowStateFilter: .unreadOnly,
                contentMode: .rollUpAlerts
            ) == "Clear notifications"
        )
        let sortTooltipValue = InboxSidebarHeader.toolbarTooltipValue(
            for: .sort,
            rowStateFilter: .unreadOnly,
            contentMode: .rollUpAlerts
        )
        #expect(sortTooltipValue.text == "Sort inbox (\(InboxSidebarKeyboardHint.toggleSort))")
        #expect(sortTooltipValue.shortcutDisplayText == ShortcutDisplayText(value: InboxSidebarKeyboardHint.toggleSort))
        #expect(sortIcon != .system(.rectangle3GroupFill))
        #expect(InboxSidebarHeader.groupIconName != InboxSidebarHeader.filterIconName)
        #expect(InboxSidebarRootContainer.surfaceBackground == .shellChrome)
        #expect(InboxSidebarContent.surfaceBackground == .shellChrome)
        #expect(InboxSidebarContent.rowLeadingInset(isGrouped: false) == 0)
        #expect(
            InboxSidebarContent.rowLeadingInset(isGrouped: true)
                == AppStyles.Shell.Sidebar.groupChildRowLeadingInset
        )
        #expect(InboxSidebarContent.showsUnreadCount(for: .byPane) == false)
        #expect(InboxSidebarContent.showsUnreadCount(for: .byRepo))
        #expect(InboxSidebarContent.showsUnreadCount(for: .byTab))
        #expect(InboxNotificationGrouping.byRepo.icon == .system(.folder))
        #expect(InboxNotificationGrouping.byPane.icon == .system(.rectangleSplit2x1))
        #expect(InboxNotificationGrouping.byTab.icon == .system(.rectangleStack))
    }
}

@MainActor
private final class InboxSidebarCommandDispatcherProbe: AppCommandDispatching {
    private let deniedCommands: Set<AppCommand>

    init(deniedCommands: Set<AppCommand>) {
        self.deniedCommands = deniedCommands
    }

    func dispatch(_: AppCommand) {}

    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}

    func canDispatch(_ command: AppCommand) -> Bool {
        !deniedCommands.contains(command)
    }

    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        true
    }

    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? {
        nil
    }

    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
