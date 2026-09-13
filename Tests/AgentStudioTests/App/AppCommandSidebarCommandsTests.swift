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
            (.showReposSidebar, "Repos", .octicon(.repo)),
            (.showPanesSidebar, "Panes", .system(.squareSplit2x1)),
            (.setReposGroupingRepo, "Repo", .octicon(.repo)),
            (.setReposGroupingActivity, "Activity", .system(.clock)),
            (.setPanesGroupingRepo, "Repo", .octicon(.repo)),
            (.setPanesGroupingTab, "Tab", .system(.squareStackFill)),
            (.setPanesGroupingActivity, "Activity", .system(.clock)),
            (.setPanesSubgroupNone, "None", .system(.circle)),
            (.setPanesSubgroupActivity, "Activity", .system(.clock)),
            (.setReposSortFieldName, "Name", .system(.line3Horizontal)),
            (.setReposSortFieldActivity, "Activity", .system(.clock)),
            (.setPanesSortFieldName, "Name", .system(.line3Horizontal)),
            (.setPanesSortFieldActivity, "Activity", .system(.clock)),
            (.toggleReposSortDirection, "Direction", .system(.arrowUpArrowDown)),
            (.togglePanesSortDirection, "Direction", .system(.arrowUpArrowDown)),
            (.toggleReposShowsPinned, "Show Pinned", .system(.pin)),
            (.togglePanesShowsPinned, "Show Pinned", .system(.pin)),
        ]

        for (command, label, icon) in expectedCommands {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.label == label)
            #expect(definition.icon == icon)
            #expect(definition.surfacePolicy.exposes(.inlineControl))
            #expect(definition.targeting == .contextual)
            #expect(command.ipcSpec.executionMode == .headless)
            #expect(command.ipcSpec.requiredPrivilege == .sidebarStateMutate)
            #expect(command.ipcSpec.argumentVariants == [.workspaceWindow])
        }
    }

    @Test("repository and pane pin commands keep independent durable targets")
    func repositoryAndPanePinCommandsKeepIndependentDurableTargets() {
        for command in [AppCommand.pinRepo, .unpinRepo] {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.targeting == .targeted([.repo]))
            #expect(command.ipcSpec.executionMode == .headless)
            #expect(command.ipcSpec.requiredPrivilege == .sidebarStateMutate)
            #expect(command.ipcSpec.argumentVariants == [.repository])
        }
        for command in [AppCommand.pinPane, .unpinPane] {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.targeting == .targeted([.pane]))
            #expect(command.ipcSpec.executionMode == .headless)
            #expect(command.ipcSpec.requiredPrivilege == .sidebarStateMutate)
            #expect(command.ipcSpec.argumentVariants == [.standalonePane])
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
            #expect(command.ipcSpec.exposure == .debugTesting)
            #expect(command.ipcSpec.resultVariants == [.unavailable])
            #expect(command.ipcSpec.argumentVariants == [.noArguments])
        }
    }
}
