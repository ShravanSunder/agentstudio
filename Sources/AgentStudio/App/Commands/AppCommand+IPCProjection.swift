import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioProgrammaticControl
import AgentStudioRepoExplorer
import Foundation

struct AppCommandIPCSpec: Equatable, Sendable {
    let exposure: AppCommandIPCExposure
    let argumentSchema: [IPCCommandArgumentSchema]
}

struct AppCommandIPCExposure: Equatable, Sendable {
    let executionModes: [IPCCommandExecutionMode]
    let targetKinds: [IPCHandleKind]
    let requiredPrivileges: [IPCPrivilegeClass]

    static func defaultInteractive(command: AppCommand, targetKinds: [IPCHandleKind]) -> Self {
        Self(
            executionModes: [.requiresInteractiveInput],
            targetKinds: targetKinds,
            requiredPrivileges: defaultRequiredPrivileges(for: command)
        )
    }

    static func uiPresentation() -> Self {
        Self(
            executionModes: [.uiPresentation],
            targetKinds: [],
            requiredPrivileges: [.uiPresent]
        )
    }

    static func headless(
        targetKinds: [IPCHandleKind] = [],
        requiredPrivileges: [IPCPrivilegeClass]
    ) -> Self {
        Self(
            executionModes: [.headless],
            targetKinds: targetKinds,
            requiredPrivileges: requiredPrivileges
        )
    }

    var commandListEntryIsHeadlessExecutable: Bool {
        executionModes.contains(.headless)
    }

    private static func defaultRequiredPrivileges(for command: AppCommand) -> [IPCPrivilegeClass] {
        switch command {
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab, .selectTab1, .selectTab2, .selectTab3, .selectTab4,
            .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .splitRight, .splitLeft,
            .equalizePanes, .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .focusPane1, .focusPane2, .focusPane3, .focusPane4,
            .focusPane5, .focusPane6, .focusPane7, .focusPane8, .focusPane9, .toggleSplitZoom,
            .minimizePane, .expandPane, .switchArrangement, .previousArrangement, .nextArrangement,
            .cycleArrangement, .saveArrangement, .deleteArrangement, .renameArrangement, .enterDrawer,
            .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9, .detachDrawerPane, .addDrawerPane, .toggleDrawer, .navigateDrawerPane,
            .closeDrawerPane, .toggleManagementLayer, .managementLayerFocusLeft,
            .managementLayerFocusRight, .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit, .toggleSidebar, .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications, .showPaneInboxNotifications,
            .clearPaneInboxNotifications, .showWorktreeSidebar, .newFloatingTerminal, .newWindow,
            .closeWindow, .openNewTerminalInTab:
            return [.layoutMutate]
        case .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt:
            return [.terminalInputWrite]
        case .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .setRepoSidebarVisibilityMode, .setRepoSidebarSortOrder,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone,
            .setInboxRowStateFilter, .setInboxContentMode,
            .addRepoFavorite, .removeRepoFavorite:
            return [.sidebarStateMutate]
        case .editPaneNote, .watchFolder, .removeRepo, .openWorktree, .openWorktreeInPane,
            .openWebview, .showBridgeReview, .showBridgeFiles,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab:
            return [.layoutMutate]
        case .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .copyCurrentPanePath, .signInGitHub, .signInGoogle, .filterSidebar, .showCommandBarEverything,
            .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
            return [.workspaceRead]
        }
    }
}

extension AppCommand {
    var ipcSpec: AppCommandIPCSpec {
        let argumentSchema: [IPCCommandArgumentSchema] =
            switch self {
            case .setRepoSidebarVisibilityMode:
                [
                    IPCCommandArgumentSchema(
                        name: "mode",
                        kind: .stringEnum(values: RepoExplorerVisibilityMode.allCases.map(\.rawValue)),
                        isRequired: true
                    )
                ]
            case .setRepoSidebarSortOrder:
                [
                    IPCCommandArgumentSchema(
                        name: "order",
                        kind: .stringEnum(values: RepoExplorerSortOrder.allCases.map(\.rawValue)),
                        isRequired: true
                    )
                ]
            case .setInboxRowStateFilter:
                [
                    IPCCommandArgumentSchema(
                        name: "filter",
                        kind: .stringEnum(values: InboxNotificationRowStateFilter.allCases.map(\.rawValue)),
                        isRequired: true
                    )
                ]
            case .setInboxContentMode:
                [
                    IPCCommandArgumentSchema(
                        name: "mode",
                        kind: .stringEnum(values: InboxNotificationContentMode.allCases.map(\.rawValue)),
                        isRequired: true
                    )
                ]
            default:
                []
            }

        let exposure: AppCommandIPCExposure =
            switch self {
            case .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
                .uiPresentation()
            case .showInboxNotifications, .showWorktreeSidebar:
                AppCommandIPCExposure(
                    executionModes: [.headless, .requiresInteractiveInput],
                    targetKinds: [],
                    requiredPrivileges: [.sidebarStateMutate]
                )
            case .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
                .setRepoSidebarVisibilityMode, .setRepoSidebarSortOrder,
                .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone,
                .setInboxRowStateFilter, .setInboxContentMode:
                .headless(requiredPrivileges: [.sidebarStateMutate])
            case .addRepoFavorite, .removeRepoFavorite:
                .headless(targetKinds: [.repo], requiredPrivileges: [.sidebarStateMutate])
            default:
                .defaultInteractive(
                    command: self,
                    targetKinds: Self.ipcTargetKinds(for: definition.appliesTo)
                )
            }

        return AppCommandIPCSpec(exposure: exposure, argumentSchema: argumentSchema)
    }

    private static func ipcTargetKinds(for searchItemTypes: Set<SearchItemType>) -> [IPCHandleKind] {
        var targetKinds: [IPCHandleKind] = []
        if searchItemTypes.contains(.tab) {
            targetKinds.append(.tab)
        }
        if searchItemTypes.contains(.repo) {
            targetKinds.append(.repo)
        }
        if searchItemTypes.contains(.pane) || searchItemTypes.contains(.floatingTerminal) {
            targetKinds.append(.pane)
        }
        return targetKinds
    }
}

extension AppCommandSpec {
    var ipcExposure: AppCommandIPCExposure {
        command.ipcSpec.exposure
    }

    var argumentSchema: [IPCCommandArgumentSchema] {
        command.ipcSpec.argumentSchema
    }

    var ipcCommandListEntry: IPCCommandListEntry {
        IPCCommandListEntry(
            id: IPCCommandIdentifier(rawValue: command.rawValue),
            title: label,
            executionModes: ipcExposure.executionModes,
            targetKinds: ipcExposure.targetKinds,
            requiredPrivileges: ipcExposure.requiredPrivileges,
            argumentSchema: argumentSchema
        )
    }
}
