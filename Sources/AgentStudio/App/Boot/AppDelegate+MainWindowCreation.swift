import AgentStudioBridge
import AgentStudioCore
import AgentStudioEditorChooser
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AppKit

struct AppDelegateMainWindowCreationDependencies {
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let octiconLoader: OcticonLoader
    let executor: WorkspaceActionExecutor
    let workspaceSurfaceCoordinator: WorkspaceSurfaceCoordinator
    let applicationLifecycleMonitor: ApplicationLifecycleMonitor
    let appLifecycleStore: AppLifecycleAtom
    let viewRegistry: ViewRegistry
    let bridgePaneAttendance: BridgePaneAttendanceAtom
    let editorChooser: EditorChooserState
    let repoExplorerSidebarPrefs: RepoExplorerSidebarPrefsAtom
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
        if viewRegistry == nil { missingDependencies.append("viewRegistry") }
        if atomStore == nil { missingDependencies.append("atomStore") }
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
            let viewRegistry,
            let atomStore,
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
            repoCache: atomStore.core.repoCache,
            octiconLoader: octiconLoader,
            executor: executor,
            workspaceSurfaceCoordinator: workspaceSurfaceCoordinator,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            viewRegistry: viewRegistry,
            bridgePaneAttendance: atomStore.bridgePaneAttendance,
            editorChooser: atomStore.editorChooser,
            repoExplorerSidebarPrefs: atomStore.repoExplorerSidebarPrefs,
            performanceTraceRecorder: performanceTraceRecorder,
            closeTransitionCoordinator: closeTransitionCoordinator
        )
    }

    func makeMainWindowController(dependencies: AppDelegateMainWindowCreationDependencies) -> MainWindowController {
        let workspaceSurfaceCoordinator = dependencies.workspaceSurfaceCoordinator
        let workspaceWindowId = UUID()
        let tabBarAdapter = TabBarAdapter(
            store: dependencies.store,
            repoCache: dependencies.repoCache,
            performanceTraceRecorder: dependencies.performanceTraceRecorder
        )
        let mainWindowController = MainWindowController(
            workspaceWindowId: workspaceWindowId,
            store: dependencies.store,
            octiconLoader: dependencies.octiconLoader,
            workspaceActionExecutor: dependencies.executor,
            runtimeCommandDispatcher: dependencies.workspaceSurfaceCoordinator,
            applicationLifecycleMonitor: dependencies.applicationLifecycleMonitor,
            appLifecycleStore: dependencies.appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: dependencies.viewRegistry,
            bridgePaneAttendance: dependencies.bridgePaneAttendance,
            editorChooser: dependencies.editorChooser,
            repoExplorerSidebarPrefs: dependencies.repoExplorerSidebarPrefs,
            bridgeAttendanceSnapshot: { paneId in
                dependencies.bridgePaneAttendance.ordinal(for: paneId)
            },
            performanceTraceRecorder: dependencies.performanceTraceRecorder,
            onSidebarVisibleWorktreesChanged: { [weak workspaceSurfaceCoordinator] in
                workspaceSurfaceCoordinator?.scheduleSidebarVisibleWorktreesUpdate()
            },
            onPerformanceProofReadback: { [weak self] readback in
                self?.receiveSidebarPerformanceProofReadback(readback)
            },
            closeTransitionCoordinator: dependencies.closeTransitionCoordinator
        )
        workspaceSurfaceCoordinator.bindBridgePaneActivities(
            toOwningWindowId: workspaceWindowId
        )
        workspaceSurfaceCoordinator.bindPullRequestDemand(
            toOwningWindowId: workspaceWindowId
        )
        return mainWindowController
    }

    private func receiveSidebarPerformanceProofReadback(
        _ readback: RepoExplorerPerformanceProofReadback
    ) {
        #if DEBUG
            sidebarPerformanceProofSession?.receive(readback)
        #else
            _ = readback
        #endif
    }
}
