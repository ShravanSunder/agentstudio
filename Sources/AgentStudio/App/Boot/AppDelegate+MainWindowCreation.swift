import AgentStudioBridge
import AgentStudioCore
import AgentStudioEditorChooser
import AgentStudioInboxNotification
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AppKit

struct AppDelegateMainWindowCreationDependencies {
    let store: WorkspaceStore
    let octiconLoader: OcticonLoader
    let executor: WorkspaceActionExecutor
    let workspaceSurfaceCoordinator: WorkspaceSurfaceCoordinator
    let applicationLifecycleMonitor: ApplicationLifecycleMonitor
    let appLifecycleStore: AppLifecycleAtom
    let tabBarAdapter: TabBarAdapter
    let viewRegistry: ViewRegistry
    let bridgePaneAttendance: BridgePaneAttendanceAtom
    let editorChooser: EditorChooserState
    let inboxNotification: InboxNotificationAtom
    let inboxNotificationPrefs: InboxNotificationPrefsAtom
    let inboxSidebarState: InboxSidebarState
    let paneInboxPresentationState: PaneInboxPresentationAtom
    let repoExplorerSidebarPrefs: RepoExplorerSidebarPrefsAtom
    let paneInboxNotificationPresenter: PaneInboxNotificationPresenter
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
}

@MainActor
extension AppDelegate {
    func mainWindowCreationMissingDependencyNames() -> [String] {
        var missingDependencies: [String] = []
        if store == nil { missingDependencies.append("store") }
        if executor == nil { missingDependencies.append("executor") }
        if workspaceSurfaceCoordinator == nil { missingDependencies.append("workspaceSurfaceCoordinator") }
        if applicationLifecycleMonitor == nil { missingDependencies.append("applicationLifecycleMonitor") }
        if appLifecycleStore == nil { missingDependencies.append("appLifecycleStore") }
        if tabBarAdapter == nil { missingDependencies.append("tabBarAdapter") }
        if viewRegistry == nil { missingDependencies.append("viewRegistry") }
        if atomStore == nil { missingDependencies.append("atomStore") }
        if paneInboxNotificationPresenter == nil { missingDependencies.append("paneInboxNotificationPresenter") }
        if performanceTraceRecorder == nil { missingDependencies.append("performanceTraceRecorder") }
        if closeTransitionCoordinator == nil { missingDependencies.append("closeTransitionCoordinator") }
        return missingDependencies
    }

    func mainWindowCreationDependencies(caller: StaticString) -> AppDelegateMainWindowCreationDependencies? {
        guard
            let store,
            let executor,
            let workspaceSurfaceCoordinator,
            let applicationLifecycleMonitor,
            let appLifecycleStore,
            let tabBarAdapter,
            let viewRegistry,
            let atomStore,
            let paneInboxNotificationPresenter,
            let performanceTraceRecorder,
            let closeTransitionCoordinator
        else {
            let callerDescription = String(describing: caller)
            let missingDependencySummary = mainWindowCreationMissingDependencyNames().joined(separator: ",")
            appLogger.warning(
                "Skipping main window creation from \(callerDescription, privacy: .public); missing dependencies: \(missingDependencySummary, privacy: .public)"
            )
            RestoreTrace.log(
                "mainWindow creation skipped caller=\(callerDescription) missingDependencies=\(missingDependencySummary)"
            )
            startupTraceRecorder.recordAppStartup(
                "app.main_window.creation.skipped",
                phase: "main_window",
                outcome: "dependencies_unavailable",
                attributes: [
                    "agentstudio.app.main_window.caller": .string(callerDescription),
                    "agentstudio.app.main_window.missing_dependencies": .string(missingDependencySummary),
                ]
            )
            return nil
        }

        return AppDelegateMainWindowCreationDependencies(
            store: store,
            octiconLoader: octiconLoader,
            executor: executor,
            workspaceSurfaceCoordinator: workspaceSurfaceCoordinator,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            bridgePaneAttendance: atomStore.bridgePaneAttendance,
            editorChooser: atomStore.editorChooser,
            inboxNotification: atomStore.inboxNotification,
            inboxNotificationPrefs: atomStore.inboxNotificationPrefs,
            inboxSidebarState: atomStore.inboxSidebarState,
            paneInboxPresentationState: atomStore.paneInboxPresentationState,
            repoExplorerSidebarPrefs: atomStore.repoExplorerSidebarPrefs,
            paneInboxNotificationPresenter: paneInboxNotificationPresenter,
            performanceTraceRecorder: performanceTraceRecorder,
            closeTransitionCoordinator: closeTransitionCoordinator
        )
    }

    func makeMainWindowController(dependencies: AppDelegateMainWindowCreationDependencies) -> MainWindowController {
        let workspaceSurfaceCoordinator = dependencies.workspaceSurfaceCoordinator
        let workspaceWindowId = UUID()
        let mainWindowController = MainWindowController(
            workspaceWindowId: workspaceWindowId,
            store: dependencies.store,
            octiconLoader: dependencies.octiconLoader,
            workspaceActionExecutor: dependencies.executor,
            runtimeCommandDispatcher: dependencies.workspaceSurfaceCoordinator,
            applicationLifecycleMonitor: dependencies.applicationLifecycleMonitor,
            appLifecycleStore: dependencies.appLifecycleStore,
            tabBarAdapter: dependencies.tabBarAdapter,
            viewRegistry: dependencies.viewRegistry,
            bridgePaneAttendance: dependencies.bridgePaneAttendance,
            editorChooser: dependencies.editorChooser,
            inboxAtom: dependencies.inboxNotification,
            inboxPrefsAtom: dependencies.inboxNotificationPrefs,
            inboxSidebarState: dependencies.inboxSidebarState,
            paneInboxPresentationState: dependencies.paneInboxPresentationState,
            repoExplorerSidebarPrefs: dependencies.repoExplorerSidebarPrefs,
            bridgeAttendanceSnapshot: {
                dependencies.bridgePaneAttendance.ordinalSnapshot()
            },
            paneInboxPresenter: dependencies.paneInboxNotificationPresenter,
            performanceTraceRecorder: dependencies.performanceTraceRecorder,
            onSidebarVisibleWorktreesChanged: { [weak workspaceSurfaceCoordinator] in
                workspaceSurfaceCoordinator?.scheduleSidebarVisibleWorktreesUpdate()
            },
            closeTransitionCoordinator: dependencies.closeTransitionCoordinator
        )
        workspaceSurfaceCoordinator.bindBridgePaneActivities(
            toOwningWindowId: workspaceWindowId
        )
        return mainWindowController
    }
}
