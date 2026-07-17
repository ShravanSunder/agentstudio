import Testing

@testable import AgentStudio

@Suite("InboxSidebarToolbarPresentation")
struct InboxSidebarToolbarPresentationTests {
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
        #expect(InboxNotificationGrouping.byRepo.icon == RepoExplorerGroupingMode.repo.icon)
        #expect(InboxNotificationGrouping.byPane.icon == RepoExplorerGroupingMode.pane.icon)
        #expect(InboxNotificationGrouping.byTab.icon == RepoExplorerGroupingMode.tab.icon)
    }
}
