import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("AppCommand sidebar commands")
struct AppCommandSidebarCommandsTests {
    @Test("repository fact update is a targeted inline-only command with no IPC exposure")
    func repositoryFactUpdateIsTargetedInlineOnlyAndNotExposedToIPC() {
        let definition = AppCommandDispatcher.shared.definition(for: .updateRepositoryFacts)

        #expect(definition.label == "Update Repository")
        #expect(definition.icon == .system(.arrowClockwise))
        #expect(definition.helpText == "Update local Git, remote references, and pull request facts")
        #expect(definition.surfacePolicy == .exposed([.inlineControl]))
        #expect(definition.targeting == .targeted([.repo]))
        #expect(definition.ipcExposure.executionModes.isEmpty)
        #expect(definition.ipcExposure.requiredPrivileges.isEmpty)
    }

    @Test("Repo sidebar grouping commands remain presented and executable")
    func repoSidebarGroupingCommandsRemainPresentedAndExecutable() {
        let expected: [(AppCommand, String, CommandIcon)] = [
            (.setRepoSidebarGroupingRepo, "Group Repos by Repo", RepoExplorerGroupingMode.repo.icon),
            (.setRepoSidebarGroupingPane, "Group Repos by Pane", RepoExplorerGroupingMode.pane.icon),
            (.setRepoSidebarGroupingTab, "Group Repos by Tab", RepoExplorerGroupingMode.tab.icon),
        ]

        for (command, label, icon) in expected {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.label == label)
            #expect(definition.icon == icon)
            #expect(definition.surfacePolicy == .exposed([.commandBar, .inlineControl]))
            #expect(definition.targeting == .contextual)
            #expect(definition.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
        }
    }

    @Test("retired Inbox sidebar commands have no presentation or IPC privilege")
    func retiredInboxSidebarCommandsHaveNoPresentationOrIPCPrivilege() {
        let commands: [AppCommand] = [
            .showInboxNotifications,
            .toggleInboxNotificationSort,
            .clearReadInboxNotifications,
            .clearAllInboxNotifications,
            .showPaneInboxNotifications,
            .clearPaneInboxNotifications,
            .setInboxGroupingTab,
            .setInboxGroupingRepo,
            .setInboxGroupingPane,
            .setInboxGroupingNone,
            .setInboxRowStateFilter,
            .setInboxContentMode,
        ]

        for command in commands {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.surfacePolicy == .notPresented)
            #expect(definition.ipcExposure.requiredPrivileges.isEmpty)
            #expect(definition.ipcExposure.executionModes.isEmpty)
        }
    }

    @Test("retired Inbox commands fail without mutating dormant preference state")
    func retiredInboxCommandsFailWithoutMutatingDormantPreferenceState() {
        let delegate = AppDelegate()
        let repoPrefs = RepoExplorerSidebarPrefsAtom()
        delegate.atomStore = AtomRegistry(repoExplorerSidebarPrefs: repoPrefs)

        #expect(delegate.execute(.setRepoSidebarGroupingPane))
        #expect(repoPrefs.groupingMode == .pane)

        #expect(!delegate.canExecute(.setInboxGroupingPane))
        #expect(!delegate.execute(.setInboxGroupingPane))
        #expect(
            delegate.execute(AppCommandExecutionRequest(command: .setInboxGroupingTab))
                == .unsupportedCommand
        )
    }

    @Test("argument-required Repo sort remains a typed headless command")
    func argumentRequiredRepoSortRemainsTypedHeadlessCommand() {
        let definition = AppCommandDispatcher.shared.definition(for: .setRepoSidebarSortOrder)

        #expect(definition.surfacePolicy == .exposed([.inlineControl]))
        #expect(
            definition.argumentSchema == [
                IPCCommandArgumentSchema(
                    name: "order",
                    kind: .stringEnum(values: ["ascending", "descending"]),
                    isRequired: true
                )
            ]
        )
        #expect(definition.ipcExposure.executionModes == [.headless])
        #expect(definition.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
    }
}
