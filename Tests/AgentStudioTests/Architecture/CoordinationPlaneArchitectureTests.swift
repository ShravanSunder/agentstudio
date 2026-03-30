import Foundation
import Testing

@Suite("CoordinationPlaneArchitectureTests")
struct CoordinationPlaneArchitectureTests {
    private struct LifecycleCompositionSources {
        let appDelegateSource: String
        let appDelegateRoutingSource: String
        let splitViewControllerSource: String
        let paneTabViewControllerSource: String
        let activeTabContentSource: String
        let singleTabContentSource: String
        let flatTabStripContainerSource: String
        let flatPaneStripContentSource: String
        let mainWindowControllerSource: String
        let paneLeafContainerSource: String
        let drawerPanelOverlaySource: String
        let drawerPanelSource: String
        let paneActionDispatchingSource: String
        let paneTabActionDispatcherSource: String
        let ghosttySource: String
        let appLifecycleStoreSource: String
        let windowLifecycleStoreSource: String
    }

    private func loadLifecycleCompositionSources(projectRoot: URL) throws -> LifecycleCompositionSources {
        try LifecycleCompositionSources(
            appDelegateSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/AppDelegate.swift"),
                encoding: .utf8
            ),
            appDelegateRoutingSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/AppDelegate+LifecycleRouting.swift"),
                encoding: .utf8
            ),
            splitViewControllerSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/MainSplitViewController.swift"),
                encoding: .utf8
            ),
            paneTabViewControllerSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Panes/PaneTabViewController.swift"),
                encoding: .utf8
            ),
            activeTabContentSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift"),
                encoding: .utf8
            ),
            singleTabContentSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift"),
                encoding: .utf8
            ),
            flatTabStripContainerSource: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift"),
                encoding: .utf8
            ),
            flatPaneStripContentSource: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift"),
                encoding: .utf8
            ),
            mainWindowControllerSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/MainWindowController.swift"),
                encoding: .utf8
            ),
            paneLeafContainerSource: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift"),
                encoding: .utf8
            ),
            drawerPanelOverlaySource: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift"),
                encoding: .utf8
            ),
            drawerPanelSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift"),
                encoding: .utf8
            ),
            paneActionDispatchingSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Actions/PaneActionDispatching.swift"),
                encoding: .utf8
            ),
            paneTabActionDispatcherSource: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Actions/PaneTabActionDispatcher.swift"
                ),
                encoding: .utf8
            ),
            ghosttySource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift"),
                encoding: .utf8
            ),
            appLifecycleStoreSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Lifecycle/AppLifecycleStore.swift"),
                encoding: .utf8
            ),
            windowLifecycleStoreSource: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Lifecycle/WindowLifecycleStore.swift"),
                encoding: .utf8
            )
        )
    }

    @Test("NotificationCenter stays limited to lifecycle allowlist")
    func notificationCenterUsage_isLifecycleOnly() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let allowedFiles: Set<String> = []

        var notificationCenterFiles: Set<String> = []
        let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: nil
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("NotificationCenter.default") || source.contains(".notifications(")
            else { continue }

            let relativePath = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            notificationCenterFiles.insert(relativePath)
        }

        #expect(notificationCenterFiles == allowedFiles)
    }

    @Test("AppDelegate owns lifecycle composition and MainSplitViewController stays out of direct lifecycle ingress")
    func lifecycleCompositionRoot_staysInAppDelegate() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegatePath = projectRoot.appending(path: "Sources/AgentStudio/App/AppDelegate.swift")
        let appDelegateRoutingPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/AppDelegate+LifecycleRouting.swift"
        )
        let applicationLifecycleMonitorPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Lifecycle/ApplicationLifecycleMonitor.swift"
        )
        let appLifecycleStorePath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Lifecycle/AppLifecycleStore.swift"
        )
        let windowLifecycleStorePath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Lifecycle/WindowLifecycleStore.swift"
        )
        let splitViewControllerPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/MainSplitViewController.swift"
        )
        let paneTabViewControllerPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Panes/PaneTabViewController.swift"
        )
        let activeTabContentPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift"
        )
        let singleTabContentPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift"
        )
        let flatTabStripContainerPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift"
        )
        let flatPaneStripContentPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift"
        )
        let paneLeafContainerPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift"
        )
        let mainWindowControllerPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/MainWindowController.swift"
        )
        let drawerPanelOverlayPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift"
        )
        let drawerPanelPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift"
        )
        let paneActionDispatchingPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Actions/PaneActionDispatching.swift"
        )
        let paneTabActionDispatcherPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Actions/PaneTabActionDispatcher.swift"
        )
        let ghosttyPath = projectRoot.appending(
            path: "Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift"
        )

        let sources = try loadLifecycleCompositionSources(projectRoot: projectRoot)

        #expect(FileManager.default.fileExists(atPath: applicationLifecycleMonitorPath.path))
        #expect(FileManager.default.fileExists(atPath: appLifecycleStorePath.path))
        #expect(FileManager.default.fileExists(atPath: windowLifecycleStorePath.path))
        #expect(sources.appDelegateSource.contains("ApplicationLifecycleMonitor"))
        #expect(sources.appDelegateSource.contains("var applicationLifecycleMonitor: ApplicationLifecycleMonitor"))
        #expect(sources.appDelegateRoutingSource.contains("Ghostty.bindApplicationLifecycleStore(appLifecycleStore)"))
        #expect(
            sources.paneTabViewControllerSource.contains("private let appLifecycleStore: AppLifecycleStore")
        )
        #expect(
            !sources.paneTabViewControllerSource.contains(
                "func setAppLifecycleStore(_ appLifecycleStore: AppLifecycleStore)"
            )
        )
        #expect(!sources.paneTabViewControllerSource.contains("replaceSplitContentView()"))
        #expect(sources.paneTabViewControllerSource.contains("tabContentHosts"))
        #expect(sources.paneTabViewControllerSource.contains("PaneTabActionDispatcher"))
        #expect(sources.mainWindowControllerSource.contains("appLifecycleStore: AppLifecycleStore"))
        #expect(sources.splitViewControllerSource.contains("appLifecycleStore: AppLifecycleStore"))
        #expect(!sources.appDelegateRoutingSource.contains("setAppLifecycleStore(appLifecycleStore)"))
        #expect(sources.activeTabContentSource.contains("let appLifecycleStore: AppLifecycleStore"))
        #expect(sources.singleTabContentSource.contains("let actionDispatcher: PaneActionDispatching"))
        #expect(sources.flatTabStripContainerSource.contains("let actionDispatcher: PaneActionDispatching"))
        #expect(sources.flatPaneStripContentSource.contains("let actionDispatcher: PaneActionDispatching"))
        #expect(sources.paneLeafContainerSource.contains("let actionDispatcher: PaneActionDispatching"))
        #expect(sources.paneActionDispatchingSource.contains("protocol PaneActionDispatching"))
        #expect(sources.paneTabActionDispatcherSource.contains("final class PaneTabActionDispatcher"))
        #expect(sources.flatTabStripContainerSource.contains("let appLifecycleStore: AppLifecycleStore"))
        #expect(sources.drawerPanelOverlaySource.contains("let appLifecycleStore: AppLifecycleStore"))
        #expect(sources.drawerPanelSource.contains("let appLifecycleStore: AppLifecycleStore"))
        #expect(!sources.ghosttySource.contains("AppLifecycleStore.shared"))
        #expect(!sources.appLifecycleStoreSource.contains("static let shared"))
        #expect(!sources.windowLifecycleStoreSource.contains("static let shared"))
        #expect(sources.splitViewControllerSource.contains("willTerminateNotification") == false)
        #expect(sources.splitViewControllerSource.contains("didBecomeActiveNotification") == false)
        #expect(sources.splitViewControllerSource.contains("didResignActiveNotification") == false)
        #expect(sources.mainWindowControllerSource.contains("windowDidBecomeKey"))
        #expect(sources.mainWindowControllerSource.contains("windowDidResignKey"))
        #expect(sources.mainWindowControllerSource.contains("handleWindowRegistered(windowId)"))
    }

    @Test("AppEvent surface excludes stale workspace-command duplicates")
    func appEventSurface_excludesStaleWorkspaceCommands() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appEventPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Events/AppEvent.swift"
        )
        let source = try String(contentsOf: appEventPath, encoding: .utf8)

        #expect(!source.contains("case newTabRequested"))
        #expect(!source.contains("case openWorktreeRequested"))
        #expect(!source.contains("case openNewTerminalRequested"))
        #expect(!source.contains("case openWorktreeInPaneRequested"))
        #expect(!source.contains("case closeTabRequested"))
        #expect(!source.contains("case undoCloseTabRequested"))
        #expect(!source.contains("case selectTabAtIndex"))
        #expect(!source.contains("case selectTabById"))
        #expect(!source.contains("case addRepoRequested"))
        #expect(!source.contains("case addFolderRequested"))
        #expect(!source.contains("case addRepoAtPathRequested"))
        #expect(!source.contains("case removeRepoRequested"))
        #expect(!source.contains("case refreshWorktreesRequested"))
        #expect(!source.contains("case extractPaneRequested"))
        #expect(!source.contains("case movePaneToTabRequested"))
        #expect(!source.contains("case openWebviewRequested"))
        #expect(!source.contains("case signInRequested"))
        #expect(!source.contains("case toggleSidebarRequested"))
        #expect(!source.contains("case filterSidebarRequested"))
        #expect(!source.contains("case refocusTerminalRequested"))
        #expect(!source.contains("case showCommandBarRepos"))
        #expect(!source.contains("case managementModeChanged"))
        #expect(source.contains("case terminalProcessTerminated"))
        #expect(!source.contains("case repairSurfaceRequested"))
        #expect(source.contains("case worktreeBellRang"))
    }

    @Test("App event bus types live under App and pane runtime channels stay app-event free")
    func appEventOwnership_staysInAppSlice() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let eventChannelsPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift"
        )
        let appEventPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Events/AppEvent.swift"
        )
        let appEventBusPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/Events/AppEventBus.swift"
        )

        let eventChannelsSource = try String(contentsOf: eventChannelsPath, encoding: .utf8)
        let appEventSource = try String(contentsOf: appEventPath, encoding: .utf8)
        let appEventBusSource = try String(contentsOf: appEventBusPath, encoding: .utf8)

        #expect(eventChannelsSource.contains("enum PaneRuntimeEventBus"))
        #expect(!eventChannelsSource.contains("enum AppEvent"))
        #expect(!eventChannelsSource.contains("enum AppEventBus"))
        #expect(!eventChannelsSource.contains("func postAppEvent"))
        #expect(!eventChannelsSource.contains("func postGhosttyEvent"))
        #expect(appEventSource.contains("enum AppEvent: Sendable"))
        #expect(appEventBusSource.contains("enum AppEventBus"))
        #expect(appEventBusSource.contains("EventBus<AppEvent>()"))
    }

    @Test("Ghostty mixed coordination bus is removed from the runtime event plane")
    func ghosttyMixedBus_isRemoved() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let eventChannelsPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift"
        )
        let ghosttyPath = projectRoot.appending(
            path: "Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift"
        )
        let surfaceManagerPath = projectRoot.appending(
            path: "Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift"
        )
        let terminalViewPath = projectRoot.appending(
            path: "Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift"
        )

        let eventChannelsSource = try String(contentsOf: eventChannelsPath, encoding: .utf8)
        let ghosttySource = try String(contentsOf: ghosttyPath, encoding: .utf8)
        let surfaceManagerSource = try String(contentsOf: surfaceManagerPath, encoding: .utf8)
        let terminalViewSource = try String(contentsOf: terminalViewPath, encoding: .utf8)

        #expect(!eventChannelsSource.contains("enum GhosttyEventSignal"))
        #expect(!eventChannelsSource.contains("enum GhosttyEventBus"))
        #expect(!ghosttySource.contains("GhosttyEventBus"))
        #expect(!surfaceManagerSource.contains("GhosttyEventBus"))
        #expect(!terminalViewSource.contains("GhosttyEventBus"))
        #expect(!ghosttySource.contains("newWindowRequested"))
    }

    @Test("Refresh worktrees is handled as app intent, not a sidebar no-op")
    func refreshWorktreesRequested_hasRealConsumer() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateRoutingPath = projectRoot.appending(
            path: "Sources/AgentStudio/App/AppDelegate+LifecycleRouting.swift"
        )
        let sidebarPath = projectRoot.appending(
            path: "Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift"
        )

        let appDelegateRoutingSource = try String(contentsOf: appDelegateRoutingPath, encoding: .utf8)
        let sidebarSource = try String(contentsOf: sidebarPath, encoding: .utf8)

        #expect(appDelegateRoutingSource.contains("func refreshWorktrees()"))
        #expect(appDelegateRoutingSource.contains("refreshWatchedFolders"))
        #expect(sidebarSource.contains("refreshWorktrees()"))
        #expect(!sidebarSource.contains("refreshWorktreesRequested"))
    }

    @Test("User-triggered command routing no longer bounces through AppEventBus")
    func userTriggeredCommandRouting_avoidsAppEventBus() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let mainSplitSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/MainSplitViewController.swift"),
            encoding: .utf8
        )
        let mainWindowSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/MainWindowController.swift"),
            encoding: .utf8
        )
        let paneTabSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Panes/PaneTabViewController.swift"),
            encoding: .utf8
        )
        let commandBarDataSourcePath =
            projectRoot
            .appending(path: "Sources/AgentStudio/Features/CommandBar")
            .appending(path: "CommandBarDataSource.swift")
        let commandBarSource = try String(
            contentsOf: commandBarDataSourcePath,
            encoding: .utf8
        )
        let paneLeafSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift"),
            encoding: .utf8
        )
        let draggableTabBarSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift"),
            encoding: .utf8
        )
        let managementModeMonitorSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/ManagementModeMonitor.swift"),
            encoding: .utf8
        )
        let managementModeShieldSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Views/ManagementModeDragShield.swift"),
            encoding: .utf8
        )

        #expect(!appDelegateSource.contains("AppEventBus.shared.subscribe()"))
        #expect(!mainSplitSource.contains("AppEventBus"))
        #expect(!mainWindowSource.contains("AppEventBus"))
        #expect(!commandBarSource.contains("AppEventBus"))
        #expect(!paneLeafSource.contains("AppEventBus"))
        #expect(!draggableTabBarSource.contains("AppEventBus"))
        #expect(!managementModeMonitorSource.contains("AppEventBus"))
        #expect(!managementModeShieldSource.contains("AppEventBus"))
        #expect(!paneTabSource.contains("case .selectTabById"))
        #expect(!paneTabSource.contains("case .undoCloseTabRequested"))
        #expect(!paneTabSource.contains("case .extractPaneRequested"))
        #expect(!paneTabSource.contains("case .movePaneToTabRequested"))
        #expect(!paneTabSource.contains("case .refocusTerminalRequested"))
        #expect(!paneTabSource.contains("case .openWebviewRequested"))
    }

    @Test("Architecture docs name the coordination planes and retired command chain")
    func coordinationPlaneDocs_describeCurrentBoundaries() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let agentsSource = try String(
            contentsOf: projectRoot.appending(path: "AGENTS.md"),
            encoding: .utf8
        )
        let readmeSource = try String(
            contentsOf: projectRoot.appending(path: "docs/architecture/README.md"),
            encoding: .utf8
        )
        let runtimeArchitectureSource = try String(
            contentsOf: projectRoot.appending(path: "docs/architecture/pane_runtime_architecture.md"),
            encoding: .utf8
        )
        let eventBusDesignSource = try String(
            contentsOf: projectRoot.appending(path: "docs/architecture/pane_runtime_eventbus_design.md"),
            encoding: .utf8
        )

        #expect(agentsSource.contains("Coordination Plane Decision Table"))
        #expect(agentsSource.contains("Workspace mutation"))
        #expect(agentsSource.contains("Runtime command"))
        #expect(agentsSource.contains("Runtime fact"))
        #expect(agentsSource.contains("AppKit/macOS lifecycle ingress"))
        #expect(agentsSource.contains("UI-only local state"))
        #expect(agentsSource.contains("AppCommand -> AppEventBus -> controller -> PaneActionCommand"))

        #expect(readmeSource.contains("Coordination Planes"))
        #expect(readmeSource.contains("ApplicationLifecycleMonitor"))
        #expect(readmeSource.contains("AppLifecycleStore"))
        #expect(readmeSource.contains("WindowLifecycleStore"))
        #expect(readmeSource.contains("@Observable"))
        #expect(readmeSource.contains("private(set)"))
        #expect(readmeSource.contains("AppCommand -> AppEventBus -> controller -> PaneActionCommand"))
        #expect(!readmeSource.contains("App-level UI intent fan-out → AppEventBus"))
        #expect(!readmeSource.contains("AppKit/macOS lifecycle only → NotificationCenter"))

        #expect(runtimeArchitectureSource.contains("ApplicationLifecycleMonitor"))
        #expect(runtimeArchitectureSource.contains("AppLifecycleStore"))
        #expect(runtimeArchitectureSource.contains("WindowLifecycleStore"))
        #expect(runtimeArchitectureSource.contains("AppCommand -> AppEventBus -> controller -> PaneActionCommand"))
        #expect(!runtimeArchitectureSource.contains("two `NotificationCenter.post` calls remain in `Ghostty.App`"))

        #expect(eventBusDesignSource.contains("AppEventBus` carries app-level notifications"))
        #expect(eventBusDesignSource.contains(".worktreeBellRang"))
        #expect(eventBusDesignSource.contains("ApplicationLifecycleMonitor"))
        #expect(eventBusDesignSource.contains("AppLifecycleStore"))
        #expect(eventBusDesignSource.contains("WindowLifecycleStore"))
        #expect(!eventBusDesignSource.contains(".repairSurfaceRequested"))
        #expect(!eventBusDesignSource.contains("defines both buses"))
    }
}
