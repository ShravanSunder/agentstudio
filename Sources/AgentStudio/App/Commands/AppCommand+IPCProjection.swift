import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioProgrammaticControl
import AgentStudioRepoExplorer
import Foundation

struct AppCommandIPCSpec: Equatable, Sendable {
    let exposure: AppCommandIPCExposure
    let argumentContract: AppCommandIPCArgumentContract

    var argumentSchema: [IPCCommandArgumentSchema] {
        argumentContract.argumentSchema
    }
}

enum AppCommandIPCExposure: Equatable, Sendable {
    case notExposed
    case interactive(
        durableTarget: AppCommandIPCDurableTargetContract,
        requiredPrivilege: IPCPrivilegeClass
    )
    case uiPresentation
    case headless(
        durableTarget: AppCommandIPCDurableTargetContract,
        requiredPrivilege: IPCPrivilegeClass
    )
    case headlessAndInteractive(
        durableTarget: AppCommandIPCDurableTargetContract,
        requiredPrivilege: IPCPrivilegeClass
    )

    var executionModes: [IPCCommandExecutionMode] {
        switch self {
        case .notExposed:
            []
        case .interactive:
            [.requiresInteractiveInput]
        case .uiPresentation:
            [.uiPresentation]
        case .headless:
            [.headless]
        case .headlessAndInteractive:
            [.headless, .requiresInteractiveInput]
        }
    }

    var durableTarget: AppCommandIPCDurableTargetContract {
        switch self {
        case .notExposed, .uiPresentation:
            .targetless
        case .interactive(let durableTarget, _),
            .headless(let durableTarget, _),
            .headlessAndInteractive(let durableTarget, _):
            durableTarget
        }
    }

    var requiredPrivileges: [IPCPrivilegeClass] {
        switch self {
        case .notExposed:
            []
        case .uiPresentation:
            [.uiPresent]
        case .interactive(_, let requiredPrivilege),
            .headless(_, let requiredPrivilege),
            .headlessAndInteractive(_, let requiredPrivilege):
            [requiredPrivilege]
        }
    }
}

enum AppCommandIPCDurableTargetContract: Equatable, Sendable {
    case targetless
    case required(
        primary: IPCHandleKind,
        additional: [IPCHandleKind]
    )

    func supports(targetType: SearchItemType) -> Bool {
        guard
            case .required(let primary, let additional) = self,
            let targetKind = targetType.ipcHandleKind
        else {
            return false
        }
        return targetKind == primary || additional.contains(targetKind)
    }
}

enum AppCommandIPCArgumentContract: Equatable, Sendable {
    case noArguments
    case repoSidebarVisibilityMode
    case repoSidebarSortOrder
    case inboxRowStateFilter
    case inboxContentMode

    var argumentSchema: [IPCCommandArgumentSchema] {
        switch self {
        case .noArguments:
            []
        case .repoSidebarVisibilityMode:
            [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: RepoExplorerVisibilityMode.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ]
        case .repoSidebarSortOrder:
            [
                IPCCommandArgumentSchema(
                    name: "order",
                    kind: .stringEnum(values: RepoExplorerSortOrder.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ]
        case .inboxRowStateFilter:
            [
                IPCCommandArgumentSchema(
                    name: "filter",
                    kind: .stringEnum(values: InboxNotificationRowStateFilter.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ]
        case .inboxContentMode:
            [
                IPCCommandArgumentSchema(
                    name: "mode",
                    kind: .stringEnum(values: InboxNotificationContentMode.allCases.map(\.rawValue)),
                    isRequired: true
                )
            ]
        }
    }
}

extension SearchItemType {
    fileprivate var ipcHandleKind: IPCHandleKind? {
        switch self {
        case .repo:
            .repo
        case .tab:
            .tab
        case .pane:
            .pane
        case .worktree, .floatingTerminal:
            nil
        }
    }
}

extension AppCommand {
    var ipcSpec: AppCommandIPCSpec {
        let argumentContract: AppCommandIPCArgumentContract =
            switch self {
            case .setRepoSidebarVisibilityMode:
                .repoSidebarVisibilityMode
            case .setRepoSidebarSortOrder:
                .repoSidebarSortOrder
            case .setInboxRowStateFilter:
                .inboxRowStateFilter
            case .setInboxContentMode:
                .inboxContentMode
            case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
                .selectTab, .nextTab, .prevTab, .selectTab1, .selectTab2, .selectTab3, .selectTab4,
                .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
                .closePane, .extractPaneToTab, .movePaneToTab, .focusPane,
                .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
                .splitRight, .splitLeft, .equalizePanes,
                .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
                .focusNextPane, .focusPrevPane,
                .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
                .focusPane6, .focusPane7, .focusPane8, .focusPane9,
                .zoomPane, .minimizePane, .expandPane,
                .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
                .saveArrangement, .deleteArrangement, .renameArrangement,
                .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft,
                .focusDrawerPaneDown, .focusDrawerPaneRight,
                .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
                .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
                .focusDrawerPane9, .detachDrawerPane, .addDrawerPane, .toggleDrawer,
                .navigateDrawerPane, .closeDrawerPane,
                .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder,
                .openPaneLocationInEditorMenu, .editPaneNote, .copyCurrentPanePath,
                .watchFolder, .removeRepo, .addRepoFavorite, .removeRepoFavorite,
                .openWorktree, .openWorktreeInPane,
                .toggleManagementLayer, .managementLayerFocusLeft, .managementLayerFocusRight,
                .managementLayerEnterDrawer, .managementLayerExitDrawer,
                .managementLayerOpenDrawer, .managementLayerCreateTerminal,
                .managementLayerCreateBrowser, .managementLayerExit,
                .toggleSidebar, .showInboxNotifications, .toggleInboxNotificationSort,
                .clearReadInboxNotifications, .clearAllInboxNotifications,
                .showPaneInboxNotifications, .clearPaneInboxNotifications, .showWorktreeSidebar,
                .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane,
                .setRepoSidebarGroupingTab,
                .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane,
                .setInboxGroupingNone,
                .newFloatingTerminal, .newWindow, .closeWindow,
                .showCommandBarEverything, .showCommandBarQuickOpen,
                .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos,
                .openWebview, .reloadBridgeWebView, .showViewer, .showBridgeReview, .showBridgeFiles,
                .openBridgeReviewInNewTab, .openBridgeFilesInNewTab,
                .signInGitHub, .signInGoogle, .filterSidebar, .openNewTerminalInTab:
                .noArguments
            }

        let exposure: AppCommandIPCExposure =
            switch self {
            case .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
                .uiPresentation
            case .zoomPane:
                .headless(
                    durableTarget: ipcDurableTargetContract,
                    requiredPrivilege: ipcRequiredPrivilege
                )
            case .showViewer:
                .notExposed
            case .reloadBridgeWebView:
                .headless(
                    durableTarget: ipcDurableTargetContract,
                    requiredPrivilege: ipcRequiredPrivilege
                )
            case .showInboxNotifications, .showWorktreeSidebar:
                .headlessAndInteractive(
                    durableTarget: ipcDurableTargetContract,
                    requiredPrivilege: ipcRequiredPrivilege
                )
            case .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
                .setRepoSidebarVisibilityMode, .setRepoSidebarSortOrder,
                .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone,
                .setInboxRowStateFilter, .setInboxContentMode:
                .headless(
                    durableTarget: ipcDurableTargetContract,
                    requiredPrivilege: ipcRequiredPrivilege
                )
            case .addRepoFavorite, .removeRepoFavorite:
                .headless(
                    durableTarget: ipcDurableTargetContract,
                    requiredPrivilege: ipcRequiredPrivilege
                )
            case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
                .selectTab, .nextTab, .prevTab, .selectTab1, .selectTab2, .selectTab3, .selectTab4,
                .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
                .closePane, .extractPaneToTab, .movePaneToTab, .focusPane,
                .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
                .splitRight, .splitLeft, .equalizePanes,
                .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
                .focusNextPane, .focusPrevPane,
                .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
                .focusPane6, .focusPane7, .focusPane8, .focusPane9,
                .minimizePane, .expandPane,
                .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
                .saveArrangement, .deleteArrangement, .renameArrangement,
                .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft,
                .focusDrawerPaneDown, .focusDrawerPaneRight,
                .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
                .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
                .focusDrawerPane9, .detachDrawerPane, .addDrawerPane, .toggleDrawer,
                .navigateDrawerPane, .closeDrawerPane,
                .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder,
                .openPaneLocationInEditorMenu, .editPaneNote, .copyCurrentPanePath,
                .watchFolder, .removeRepo, .openWorktree, .openWorktreeInPane,
                .toggleManagementLayer, .managementLayerFocusLeft, .managementLayerFocusRight,
                .managementLayerEnterDrawer, .managementLayerExitDrawer,
                .managementLayerOpenDrawer, .managementLayerCreateTerminal,
                .managementLayerCreateBrowser, .managementLayerExit,
                .toggleSidebar, .toggleInboxNotificationSort,
                .clearReadInboxNotifications, .clearAllInboxNotifications,
                .showPaneInboxNotifications, .clearPaneInboxNotifications,
                .newFloatingTerminal, .newWindow, .closeWindow,
                .showCommandBarQuickOpen, .openWebview,
                .showBridgeReview, .showBridgeFiles,
                .openBridgeReviewInNewTab, .openBridgeFilesInNewTab,
                .signInGitHub, .signInGoogle, .filterSidebar, .openNewTerminalInTab:
                .interactive(
                    durableTarget: ipcDurableTargetContract,
                    requiredPrivilege: ipcRequiredPrivilege
                )
            }

        return AppCommandIPCSpec(
            exposure: exposure,
            argumentContract: argumentContract
        )
    }

    /// Declares the durable handle kinds accepted by the IPC command plane.
    ///
    /// Interactive targeting answers where an in-process UI may attach a command.
    /// It is intentionally not an IPC authorization or discovery source.
    private var ipcDurableTargetContract: AppCommandIPCDurableTargetContract {
        switch self {
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .selectTab,
            .equalizePanes, .switchArrangement, .saveArrangement, .deleteArrangement,
            .renameArrangement:
            return .required(primary: .tab, additional: [])
        case .splitRight, .splitLeft:
            return .required(primary: .tab, additional: [.pane])
        case .removeRepo, .addRepoFavorite, .removeRepoFavorite:
            return .required(primary: .repo, additional: [])
        case .closePane, .extractPaneToTab, .movePaneToTab, .focusPane,
            .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .zoomPane, .minimizePane, .expandPane, .enterDrawer,
            .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight, .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane, .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .editPaneNote,
            .copyCurrentPanePath, .reloadBridgeWebView,
            .showPaneInboxNotifications, .clearPaneInboxNotifications:
            return .required(primary: .pane, additional: [])
        case .newTab, .undoCloseTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .previousArrangement, .nextArrangement, .cycleArrangement,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9, .watchFolder, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer, .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal,
            .managementLayerCreateBrowser, .managementLayerExit, .toggleSidebar,
            .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications, .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane,
            .setRepoSidebarGroupingTab, .setRepoSidebarVisibilityMode,
            .setRepoSidebarSortOrder, .setInboxGroupingTab, .setInboxGroupingRepo,
            .setInboxGroupingPane, .setInboxGroupingNone, .setInboxRowStateFilter,
            .setInboxContentMode, .newFloatingTerminal, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarQuickOpen, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos, .openWebview, .showViewer,
            .showBridgeReview, .showBridgeFiles, .openBridgeReviewInNewTab,
            .openBridgeFilesInNewTab, .signInGitHub, .signInGoogle, .filterSidebar,
            .openNewTerminalInTab:
            return .targetless
        }
    }

    private var ipcRequiredPrivilege: IPCPrivilegeClass {
        switch self {
        case .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos:
            return .uiPresent
        case .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt:
            return .terminalInputWrite
        case .showInboxNotifications, .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane,
            .setRepoSidebarGroupingTab, .setRepoSidebarVisibilityMode,
            .setRepoSidebarSortOrder, .setInboxGroupingTab, .setInboxGroupingRepo,
            .setInboxGroupingPane, .setInboxGroupingNone, .setInboxRowStateFilter,
            .setInboxContentMode, .addRepoFavorite, .removeRepoFavorite:
            return .sidebarStateMutate
        case .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder,
            .openPaneLocationInEditorMenu, .copyCurrentPanePath, .reloadBridgeWebView,
            .showCommandBarQuickOpen, .signInGitHub, .signInGoogle, .filterSidebar:
            return .workspaceRead
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab, .selectTab1, .selectTab2, .selectTab3, .selectTab4,
            .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .zoomPane, .minimizePane, .expandPane,
            .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
            .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft,
            .focusDrawerPaneDown, .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9, .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane, .editPaneNote,
            .watchFolder, .removeRepo, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer, .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal,
            .managementLayerCreateBrowser, .managementLayerExit,
            .toggleSidebar, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .newFloatingTerminal, .newWindow, .closeWindow,
            .openWebview, .showViewer, .showBridgeReview, .showBridgeFiles,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab,
            .openNewTerminalInTab:
            return .layoutMutate
        }
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
        let targetKinds: [IPCHandleKind] =
            switch ipcExposure.durableTarget {
            case .targetless:
                []
            case .required(let primary, let additional):
                [primary] + additional
            }

        return IPCCommandListEntry(
            id: IPCCommandIdentifier(rawValue: command.rawValue),
            title: label,
            executionModes: ipcExposure.executionModes,
            targetKinds: targetKinds,
            requiredPrivileges: ipcExposure.requiredPrivileges,
            argumentSchema: argumentSchema
        )
    }
}
