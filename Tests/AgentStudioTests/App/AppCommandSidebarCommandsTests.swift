import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("AppCommand sidebar commands")
struct AppCommandSidebarCommandsTests {
    @Test("sidebar settings expose compact surface-specific command specs")
    func sidebarSettingsExposeCompactSurfaceSpecificCommandSpecs() {
        let expectedCommands: [(AppCommand, String, CommandIcon)] = [
            (.showReposSidebar, "Repos", .system(.folder)),
            (.showPanesSidebar, "Panes", .system(.rectangleSplit2x1)),
            (.setReposGroupingRepo, "Repo", .system(.folder)),
            (.setPanesGroupingRepo, "Repo", .system(.folder)),
            (.setPanesGroupingTab, "Tab", .system(.rectangleStack)),
            (.setPanesGroupingActivity, "Activity", .system(.clock)),
            (.setReposSubgroupNone, "None", .system(.circle)),
            (.setReposSubgroupActivity, "Activity", .system(.clock)),
            (.setPanesSubgroupNone, "None", .system(.circle)),
            (.setPanesSubgroupActivity, "Activity", .system(.clock)),
            (.setReposSortFieldName, "Name", .system(.line3Horizontal)),
            (.setReposSortFieldActivity, "Activity", .system(.clock)),
            (.setPanesSortFieldName, "Name", .system(.line3Horizontal)),
            (.setPanesSortFieldActivity, "Activity", .system(.clock)),
            (.toggleReposSortDirection, "Direction", .system(.arrowUp)),
            (.togglePanesSortDirection, "Direction", .system(.arrowUp)),
            (.toggleReposShowsPinned, "Show Pinned", .system(.pinFill)),
            (.togglePanesShowsPinned, "Show Pinned", .system(.pinFill)),
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
