import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("AppCommand sidebar commands", .serialized)
struct AppCommandSidebarCommandsTests {
    @Test("focus sidebar is an interactive UI-presentation command")
    func focusSidebarIsInteractiveUIPresentationCommand() {
        let definition = AppCommandDispatcher.shared.definition(for: .focusSidebar)

        #expect(definition.label == "Focus Sidebar")
        #expect(definition.icon == .system(.keyboard))
        #expect(definition.shortcut == .focusSidebar)
        #expect(definition.surfacePolicy == .exposed([.commandBar, .inlineControl]))
        #expect(definition.targeting == .contextual)
        #expect(definition.ipcExposure == .uiPresentation)
        #expect(definition.argumentSchema.isEmpty)
    }

    @Test("sidebar settings expose compact surface-specific command specs")
    func sidebarSettingsExposeCompactSurfaceSpecificCommandSpecs() {
        let expectedCommands: [(AppCommand, String, CommandIcon)] = [
            (.showReposSidebar, "Repos", .octicon(.repo)),
            (.showPanesSidebar, "Panes", .system(.squareSplit2x1)),
            (.setReposGroupingRepo, "Repo", .octicon(.repo)),
            (.setReposGroupingActivity, "Activity", .system(.clock)),
            (.setReposSortFieldName, "Name", .system(.line3Horizontal)),
            (.setReposSortFieldActivity, "Activity", .system(.clock)),
            (.toggleReposSortDirection, "Direction", .system(.arrowUpArrowDown)),
            (.toggleReposShowsPinned, "Show Pinned", .system(.pin)),
            (.togglePanesShowsPinned, "Show Pinned", .system(.pin)),
        ]

        for (command, label, icon) in expectedCommands {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.label == label)
            #expect(definition.icon == icon)
            #expect(definition.surfacePolicy.exposes(.inlineControl))
            #expect(definition.targeting == .contextual)
            let expectedExecutionModes: [IPCCommandExecutionMode] =
                command == .showReposSidebar || command == .showPanesSidebar
                ? [.headless, .requiresInteractiveInput]
                : [.headless]
            #expect(definition.ipcExposure.executionModes == expectedExecutionModes)
            #expect(definition.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
            #expect(definition.argumentSchema.isEmpty)
        }
    }

    @Test("fixed Panes organization has no interactive or IPC setting commands")
    func fixedPanesOrganizationHasNoSettingCommands() {
        for command in [
            AppCommand.setPanesGroupingRepo, .setPanesGroupingTab, .setPanesGroupingActivity,
            .setPanesSubgroupNone, .setPanesSubgroupActivity,
            .setPanesSortFieldName, .setPanesSortFieldActivity, .togglePanesSortDirection,
        ] {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.surfacePolicy == .notPresented)
            #expect(definition.ipcExposure.requiredPrivileges.isEmpty)
            #expect(definition.ipcExposure.executionModes.isEmpty)
        }
    }

    @Test("repository and pane pin commands keep independent durable targets")
    func repositoryAndPanePinCommandsKeepIndependentDurableTargets() {
        for command in [AppCommand.pinRepo, .unpinRepo] {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.targeting == .targeted([.repo]))
            #expect(definition.ipcExposure.executionModes == [.headless])
            #expect(definition.ipcExposure.requiredPrivileges == [.sidebarStateMutate])
        }
        for command in [AppCommand.pinPane, .unpinPane] {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.targeting == .targeted([.pane]))
            #expect(definition.ipcExposure.executionModes == [.headless])
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
}
