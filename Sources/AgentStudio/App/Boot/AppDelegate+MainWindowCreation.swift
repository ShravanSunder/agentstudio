import AppKit

struct AppDelegateMainWindowCreationDependencies {
    let store: WorkspaceStore
    let executor: WorkspaceActionExecutor
    let workspaceSurfaceCoordinator: WorkspaceSurfaceCoordinator
    let applicationLifecycleMonitor: ApplicationLifecycleMonitor
    let appLifecycleStore: AppLifecycleAtom
    let tabBarAdapter: TabBarAdapter
    let viewRegistry: ViewRegistry
    let atomStore: AtomRegistry
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
            executor: executor,
            workspaceSurfaceCoordinator: workspaceSurfaceCoordinator,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            atomStore: atomStore,
            paneInboxNotificationPresenter: paneInboxNotificationPresenter,
            performanceTraceRecorder: performanceTraceRecorder,
            closeTransitionCoordinator: closeTransitionCoordinator
        )
    }

    func makeMainWindowController(dependencies: AppDelegateMainWindowCreationDependencies) -> MainWindowController {
        let workspaceSurfaceCoordinator = dependencies.workspaceSurfaceCoordinator
        return MainWindowController(
            store: dependencies.store,
            workspaceActionExecutor: dependencies.executor,
            runtimeCommandDispatcher: dependencies.workspaceSurfaceCoordinator,
            applicationLifecycleMonitor: dependencies.applicationLifecycleMonitor,
            appLifecycleStore: dependencies.appLifecycleStore,
            tabBarAdapter: dependencies.tabBarAdapter,
            viewRegistry: dependencies.viewRegistry,
            inboxAtom: dependencies.atomStore.inboxNotification,
            inboxPrefsAtom: dependencies.atomStore.inboxNotificationPrefs,
            inboxSidebarState: dependencies.atomStore.inboxSidebarState,
            paneInboxPresenter: dependencies.paneInboxNotificationPresenter,
            performanceTraceRecorder: dependencies.performanceTraceRecorder,
            onSidebarVisibleWorktreesChanged: { [weak workspaceSurfaceCoordinator] in
                workspaceSurfaceCoordinator?.syncFilesystemRootsAndActivity()
            },
            closeTransitionCoordinator: dependencies.closeTransitionCoordinator
        )
    }
}
