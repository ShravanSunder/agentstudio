import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio

@MainActor
@Suite("AppCommand sidebar commands")
struct AppCommandSidebarCommandsTests {
    @Test("dispatcher registers sidebar grouping commands")
    func dispatcherRegistersSidebarGroupingCommands() {
        let expected: [(AppCommand, String, CommandIcon)] = [
            (.setRepoSidebarGroupingRepo, "Group Repos by Repo", RepoExplorerGroupingMode.repo.icon),
            (.setRepoSidebarGroupingPane, "Group Repos by Pane", RepoExplorerGroupingMode.pane.icon),
            (.setRepoSidebarGroupingTab, "Group Repos by Tab", RepoExplorerGroupingMode.tab.icon),
            (.setInboxGroupingTab, "Group Inbox by Tab", InboxNotificationGrouping.byTab.icon),
            (.setInboxGroupingRepo, "Group Inbox by Repo", InboxNotificationGrouping.byRepo.icon),
            (.setInboxGroupingPane, "Group Inbox by Pane", InboxNotificationGrouping.byPane.icon),
            (.setInboxGroupingNone, "Group Inbox by None", InboxNotificationGrouping.none.icon),
        ]

        for (command, label, icon) in expected {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.label == label)
            #expect(definition.icon == icon)
            #expect(definition.commandBarGroupName == (command.rawValue.hasPrefix("setInbox") ? "Inbox" : "Sidebar"))
            #expect(!definition.isHiddenInCommandBar)
        }
    }

    @Test("dispatcher registers repo sidebar visibility mode command for headless execution")
    func dispatcherRegistersRepoSidebarVisibilityModeCommandForHeadlessExecution() {
        let definition = AppCommandDispatcher.shared.definition(for: .setRepoSidebarVisibilityMode)

        #expect(definition.label == "Set Repo Sidebar Visibility Mode")
        #expect(definition.icon == .system(.bookmark))
        #expect(definition.commandBarGroupName == "Sidebar")
        #expect(definition.isHiddenInCommandBar)
        #expect(definition.ipcExposure.executionModes == [.headless])
        #expect(definition.ipcExposure.targetKinds.isEmpty)
        #expect(definition.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
    }

    @Test("dispatcher registers repo sidebar sort order command for headless execution")
    func dispatcherRegistersRepoSidebarSortOrderCommandForHeadlessExecution() {
        let definition = AppCommandDispatcher.shared.definition(for: .setRepoSidebarSortOrder)

        #expect(definition.label == "Set Repo Sidebar Sort Order")
        #expect(definition.icon == .system(.arrowUpArrowDown))
        #expect(definition.commandBarGroupName == "Sidebar")
        #expect(definition.isHiddenInCommandBar)
        #expect(
            definition.argumentSchema == [
                IPCCommandArgumentSchema(
                    name: "order",
                    kind: .stringEnum(values: ["ascending", "descending"]),
                    isRequired: true
                )
            ])
        #expect(definition.ipcExposure.executionModes == [.headless])
        #expect(definition.ipcExposure.targetKinds.isEmpty)
        #expect(definition.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
    }

    @Test("dispatcher registers typed inbox filter commands for headless execution")
    func dispatcherRegistersTypedInboxFilterCommandsForHeadlessExecution() {
        let rowFilter = AppCommandDispatcher.shared.definition(for: .setInboxRowStateFilter)
        let contentMode = AppCommandDispatcher.shared.definition(for: .setInboxContentMode)

        #expect(rowFilter.icon == .system(.envelopeBadge))
        #expect(
            rowFilter.argumentSchema == [
                IPCCommandArgumentSchema(
                    name: "filter",
                    kind: .stringEnum(values: ["unreadOnly", "all"]),
                    isRequired: true
                )
            ])
        #expect(contentMode.icon == .system(.dotCircleViewfinder))
        #expect(
            contentMode.argumentSchema == [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: ["rollUpAlerts", "activity", "all"]),
                    isRequired: true
                )
            ])
        #expect(rowFilter.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
        #expect(contentMode.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
    }
}
