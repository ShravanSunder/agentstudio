import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation

/// Typed `command.execute` delivery into the App shell's existing owners.
///
/// The shell owns window lifecycle, sidebar chrome and preferences, command-bar
/// and authentication presentation, the watch-folder owner and repository fact
/// refresh. Every other command returns `.unsupportedCommand` so the dispatcher
/// falls through to the workspace owner, exactly as the interactive path does.
extension AppDelegate {
    func executeTypedIPCShellCommand(
        _ command: AppCommand,
        arguments: IPCCommandArguments
    ) -> AppCommandExecutionOutcome {
        switch arguments {
        case .noArguments:
            return executeWindowlessShellCommand(command)
        case .workspaceWindow:
            return executeWindowScopedShellCommand(command)
        case .directory(let value):
            return executeWatchFolderCommand(command, directoryPath: value.directoryPath)
        case .repository(let value):
            return executeRepositoryShellCommand(command, repoId: value.repoId)
        default:
            return .unsupportedCommand
        }
    }

    private func executeWindowlessShellCommand(_ command: AppCommand) -> AppCommandExecutionOutcome {
        switch command {
        case .newWindow:
            newWindow()
            return .applied
        case .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane,
            .setInboxGroupingNone, .setInboxRowStateFilter, .setInboxContentMode:
            // The Inbox feature is dormant. Report that honestly instead of
            // reviving a surface no owner currently implements.
            return .unavailable(.featureUnavailable)
        default:
            return .unsupportedCommand
        }
    }

    private func executeWindowScopedShellCommand(_ command: AppCommand) -> AppCommandExecutionOutcome {
        switch command {
        case .setPanesGroupingRepo, .setPanesGroupingTab, .setPanesGroupingActivity,
            .setPanesSubgroupNone, .setPanesSubgroupActivity,
            .setPanesSortFieldName, .setPanesSortFieldActivity, .togglePanesSortDirection:
            // Retired Panes-organization settings. No owner may be revived here.
            return .unavailable(.featureUnavailable)
        case .closeWindow:
            closeWindow()
            return .applied
        case .toggleSidebar:
            guard let mainWindowController else { return .stateUnavailable }
            mainWindowController.toggleSidebar()
            return .applied
        case .filterSidebar:
            guard let mainWindowController else { return .stateUnavailable }
            mainWindowController.showSidebarFilter()
            return .presented
        case .showCommandBarEverything, .showCommandBarQuickOpen, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos:
            guard execute(command) else { return .stateUnavailable }
            return .presented
        case .signInGitHub, .signInGoogle:
            // Presentation reports initiation. Sign-in completion is a later
            // user action this receipt never claims.
            guard execute(command) else { return .stateUnavailable }
            return .presented
        case .showReposSidebar, .showPanesSidebar,
            .setReposGroupingRepo, .setReposGroupingActivity,
            .setReposSortFieldName, .setReposSortFieldActivity,
            .toggleReposSortDirection, .toggleReposShowsPinned, .togglePanesShowsPinned:
            return execute(AppCommandExecutionRequest(command: command))
        default:
            return .unsupportedCommand
        }
    }

    private func executeWatchFolderCommand(
        _ command: AppCommand,
        directoryPath: String
    ) -> AppCommandExecutionOutcome {
        guard command == .watchFolder else { return .unsupportedCommand }
        let directory = URL(fileURLWithPath: directoryPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return .unavailable(.noApplicableTarget)
        }
        // The watch-folder owner persists the path and then scans. The scan is
        // long-running, so this receipt is acceptance, not completion.
        Task { await handleWatchFolderRequested(startingAt: directory) }
        return .accepted(operationId: nil)
    }

    private func executeRepositoryShellCommand(
        _ command: AppCommand,
        repoId: UUID
    ) -> AppCommandExecutionOutcome {
        guard command == .updateRepositoryFacts else { return .unsupportedCommand }
        // The fact-update owner starts a tracked refresh attempt and settles it
        // later, so the receipt is acceptance.
        guard execute(command, target: repoId, targetType: .repo) else {
            return .stateUnavailable
        }
        return .accepted(operationId: nil)
    }
}
