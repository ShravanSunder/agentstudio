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

    @Test("sidebar grouping commands require available preference state")
    func sidebarGroupingCommandsRequireAvailablePreferenceState() {
        let delegate = AppDelegate()
        #expect(!delegate.execute(.setRepoSidebarGroupingPane))
        #expect(!delegate.execute(.setInboxGroupingPane))

        let repoPrefs = RepoExplorerSidebarPrefsAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        delegate.atomStore = AtomRegistry(
            repoExplorerSidebarPrefs: repoPrefs,
            inboxNotificationPrefs: inboxPrefs
        )

        #expect(delegate.execute(.setRepoSidebarGroupingPane))
        #expect(repoPrefs.groupingMode == .pane)
        #expect(delegate.execute(.setInboxGroupingPane))
        #expect(inboxPrefs.grouping == .byPane)
    }

    @Test("dispatcher registers repo sidebar visibility mode command for headless execution")
    func dispatcherRegistersRepoSidebarVisibilityModeCommandForHeadlessExecution() {
        let definition = AppCommandDispatcher.shared.definition(for: .setRepoSidebarVisibilityMode)

        #expect(definition.label == "Set Repo Sidebar Visibility Mode")
        #expect(definition.icon == .system(.bookmark))
        #expect(definition.commandBarGroupName == "Sidebar")
        #expect(definition.isHiddenInCommandBar)
        #expect(
            definition.argumentSchema == [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: ["all", "favoritesOnly"]),
                    isRequired: true
                )
            ])
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

    @Test("sidebar commands use sidebar mutation privileges")
    func sidebarCommandsUseSidebarMutationPrivileges() {
        let commands: [AppCommand] = [
            .setRepoSidebarGroupingRepo,
            .setRepoSidebarGroupingPane,
            .setRepoSidebarGroupingTab,
            .setRepoSidebarVisibilityMode,
            .setRepoSidebarSortOrder,
            .setInboxGroupingTab,
            .setInboxGroupingRepo,
            .setInboxGroupingPane,
            .setInboxGroupingNone,
            .setInboxRowStateFilter,
            .setInboxContentMode,
        ]

        for command in commands {
            #expect(command.definition.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
        }
    }

    @Test("argument-required sidebar commands are not parameterless actions")
    func argumentRequiredSidebarCommandsAreNotParameterlessActions() {
        let delegate = AppDelegate()
        delegate.atomStore = AtomRegistry(
            repoExplorerSidebarPrefs: RepoExplorerSidebarPrefsAtom(),
            inboxNotificationPrefs: InboxNotificationPrefsAtom()
        )

        #expect(!delegate.canExecute(.setRepoSidebarVisibilityMode))
        #expect(!delegate.canExecute(.setRepoSidebarSortOrder))
        #expect(!delegate.canExecute(.setInboxRowStateFilter))
        #expect(!delegate.canExecute(.setInboxContentMode))
    }
}
