import Foundation
import Testing

@Suite("Application entrypoint architecture")
struct ApplicationEntrypointArchitectureTests {
    @Test("manual NSApplication setup uses a single run loop")
    func manualNSApplicationSetupUsesSingleRunLoop() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let mainSourceURL = projectRoot.appending(path: "Sources/AgentStudio/main.swift")
        let source = try String(contentsOf: mainSourceURL, encoding: .utf8)

        #expect(source.contains("let app = NSApplication.shared"))
        #expect(source.contains("app.delegate = delegate"))
        #expect(source.contains("UserDefaults.standard.set(false, forKey: \"NSQuitAlwaysKeepsWindows\")"))
        #expect(source.contains("app.run()"))
        #expect(!source.contains("NSApplicationMain("))
    }

    @Test("structured tracing is bootstrapped before Ghostty initialization")
    func structuredTracingBootstrapsBeforeGhosttyInitialization() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let mainSourceURL = projectRoot.appending(path: "Sources/AgentStudio/main.swift")
        let appDelegateURL = projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift")
        let workspaceBootURL = projectRoot.appending(
            path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift")

        let mainSource = try String(contentsOf: mainSourceURL, encoding: .utf8)
        let appDelegateSource = try String(contentsOf: appDelegateURL, encoding: .utf8)
        let workspaceBootSource = try String(contentsOf: workspaceBootURL, encoding: .utf8)

        let traceBootstrapIndex = try #require(
            mainSource.range(of: "let traceRuntime = AgentStudioTraceRuntime.fromEnvironment()")?.lowerBound)
        let ghosttyInitIndex = try #require(mainSource.range(of: "ghostty_init(argc, argv)")?.lowerBound)
        let appDelegateInjectionIndex = try #require(
            mainSource.range(of: "startupTraceRecorder: startupTraceRecorder")?.lowerBound)

        #expect(traceBootstrapIndex < ghosttyInitIndex)
        #expect(appDelegateInjectionIndex > ghosttyInitIndex)
        #expect(appDelegateSource.contains("startupTraceRecorder: AgentStudioStartupTraceRecorder"))
        #expect(mainSource.contains("startupTraceRecorder: startupTraceRecorder"))
        #expect(!workspaceBootSource.contains("traceRuntime = .fromEnvironment()"))
        #expect(workspaceBootSource.contains("makeWorkspaceSQLiteDatastore(traceRuntime: traceRuntime)"))
    }

    @Test("startup diagnostic trigger is opt in and routes through AppCommandDispatcher")
    func startupDiagnosticTriggerIsOptInAndRoutesThroughCommandDispatcher() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateURL = projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift")
        let startupDiagnosticsURL = projectRoot.appending(
            path: "Sources/AgentStudio/App/Boot/AppDelegate+StartupDiagnostics.swift")
        let diagnosticActionURL = projectRoot.appending(
            path: "Sources/AgentStudio/App/Boot/AgentStudioStartupDiagnosticAction.swift")

        let appDelegateSource = try String(contentsOf: appDelegateURL, encoding: .utf8)
        let startupDiagnosticsSource = try String(contentsOf: startupDiagnosticsURL, encoding: .utf8)
        let diagnosticActionSource = try String(contentsOf: diagnosticActionURL, encoding: .utf8)

        let presentationCompleteIndex = try #require(
            appDelegateSource.range(of: "mainWindowController?.completeLaunchPresentation()")?.lowerBound)
        let diagnosticTriggerIndex = try #require(
            appDelegateSource.range(of: "runStartupDiagnosticActionIfRequested()")?.lowerBound)

        #expect(presentationCompleteIndex < diagnosticTriggerIndex)
        #expect(diagnosticActionSource.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION"))
        let actionDebugGuardIndex = try #require(diagnosticActionSource.range(of: "#if DEBUG")?.lowerBound)
        let actionSmokeCaseIndex = try #require(
            diagnosticActionSource.range(of: "case crossTabMoveGeometrySmoke")?.lowerBound)
        let actionIPCSmokeCaseIndex = try #require(
            diagnosticActionSource.range(of: "case ipcTerminalSmoke")?.lowerBound)
        let actionDebugEndIndex = try #require(diagnosticActionSource.range(of: "#endif")?.lowerBound)
        #expect(actionDebugGuardIndex < actionSmokeCaseIndex)
        #expect(actionSmokeCaseIndex < actionDebugEndIndex)
        #expect(actionDebugGuardIndex < actionIPCSmokeCaseIndex)
        #expect(actionIPCSmokeCaseIndex < actionDebugEndIndex)
        #expect(startupDiagnosticsSource.contains("AgentStudioStartupDiagnosticAction.fromEnvironment()"))
        #expect(startupDiagnosticsSource.contains("AppCommandDispatcher.shared.dispatch(.newTab)"))
        #expect(startupDiagnosticsSource.contains("AppCommandDispatcher.shared.dispatch(.showCommandBarEverything)"))
        #expect(startupDiagnosticsSource.contains("commandBarController.state.rawInput = \"# repo\""))
        #expect(startupDiagnosticsSource.contains("handleWatchFolderRequested(startingAt: folderURL)"))
        let dispatchDebugGuardIndex = try #require(startupDiagnosticsSource.range(of: "#if DEBUG")?.lowerBound)
        let dispatchSmokeCaseIndex = try #require(
            startupDiagnosticsSource.range(of: "case .crossTabMoveGeometrySmoke")?.lowerBound)
        let dispatchIPCSmokeCaseIndex = try #require(
            startupDiagnosticsSource.range(of: "case .ipcTerminalSmoke")?.lowerBound)
        let dispatchDebugEndIndex = try #require(startupDiagnosticsSource.range(of: "#endif")?.lowerBound)
        #expect(dispatchDebugGuardIndex < dispatchSmokeCaseIndex)
        #expect(dispatchSmokeCaseIndex < dispatchDebugEndIndex)
        #expect(dispatchDebugGuardIndex < dispatchIPCSmokeCaseIndex)
        #expect(dispatchIPCSmokeCaseIndex < dispatchDebugEndIndex)
        #expect(startupDiagnosticsSource.contains("WindowRestoreBridge(windowLifecycleStore: windowLifecycleStore)"))
        #expect(startupDiagnosticsSource.contains("isReadyForLaunchRestore"))
        let diagnosticActivateIndex = try #require(
            startupDiagnosticsSource.range(of: "NSApp.activate(ignoringOtherApps: true)")?.lowerBound)
        let diagnosticKeyWindowIndex = try #require(
            startupDiagnosticsSource.range(of: "mainWindowController?.window?.makeKeyAndOrderFront(nil)")?.lowerBound)
        let diagnosticActivationWaitIndex = try #require(
            startupDiagnosticsSource.range(of: "await waitForStartupDiagnosticAppActivation()")?.lowerBound)
        let diagnosticOpenTerminalIndex = try #require(
            startupDiagnosticsSource.range(of: "workspaceSurfaceCoordinator.openFloatingTerminal(")?.lowerBound)
        #expect(diagnosticActivateIndex < diagnosticKeyWindowIndex)
        #expect(diagnosticKeyWindowIndex < diagnosticActivationWaitIndex)
        #expect(diagnosticActivationWaitIndex < diagnosticOpenTerminalIndex)
        #expect(startupDiagnosticsSource.contains("AppPolicies.StartupDiagnostic.appActivationTimeout"))
        #expect(startupDiagnosticsSource.contains("workspaceSurfaceCoordinator.openFloatingTerminal("))
        #expect(startupDiagnosticsSource.contains("provider: .zmx"))
        #expect(startupDiagnosticsSource.contains("app.startup_diagnostic_action.command_exercised"))
        #expect(startupDiagnosticsSource.contains("app.startup_diagnostic_action.blocked"))
        #expect(!startupDiagnosticsSource.contains("for _ in 0..<80"))
        #expect(diagnosticActionSource.contains("AGENTSTUDIO_STARTUP_WATCH_FOLDER"))
        #expect(!appDelegateSource.contains("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION"))
    }

    @Test("AppKit persistent UI restoration is disabled")
    func appKitPersistentUIRestorationIsDisabled() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateURL = projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift")
        let mainWindowControllerURL = projectRoot.appending(
            path: "Sources/AgentStudio/App/Windows/MainWindowController.swift")

        let appDelegateSource = try String(contentsOf: appDelegateURL, encoding: .utf8)
        let mainWindowControllerSource = try String(contentsOf: mainWindowControllerURL, encoding: .utf8)
        let secureRestorationDisabled =
            "    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {\n"
            + "        false\n"
            + "    }"

        #expect(appDelegateSource.contains(secureRestorationDisabled))
        #expect(mainWindowControllerSource.contains("window.isRestorable = false"))
    }

    @Test("App IPC server is composed at app boot and stopped on termination")
    func appIPCServerIsComposedAtAppBootAndStoppedOnTermination() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateURL = projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift")
        let ipcBootURL = projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift")
        let terminationURL = projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift")
        let mainWindowControllerURL = projectRoot.appending(
            path: "Sources/AgentStudio/App/Windows/MainWindowController.swift")
        let splitViewControllerURL = projectRoot.appending(
            path: "Sources/AgentStudio/App/Windows/MainSplitViewController.swift")

        let appDelegateSource = try String(contentsOf: appDelegateURL, encoding: .utf8)
        let ipcBootSource = try String(contentsOf: ipcBootURL, encoding: .utf8)
        let terminationSource = try String(contentsOf: terminationURL, encoding: .utf8)
        let mainWindowControllerSource = try String(contentsOf: mainWindowControllerURL, encoding: .utf8)
        let splitViewControllerSource = try String(contentsOf: splitViewControllerURL, encoding: .utf8)

        let lifecycleConsumerIndex = try #require(appDelegateSource.range(of: "wireLifecycleConsumers()")?.lowerBound)
        let appIPCStartIndex = try #require(appDelegateSource.range(of: "startAppIPCServer()")?.lowerBound)
        let appIPCStopIndex = try #require(terminationSource.range(of: "stopAppIPCServer()")?.lowerBound)
        let flushStoresIndex = try #require(terminationSource.range(of: "await store.flushAsync()")?.lowerBound)

        #expect(appDelegateSource.contains("import AgentStudioAppIPC"))
        #expect(appDelegateSource.contains("var appIPCServer: AgentStudioAppIPCServer?"))
        #expect(lifecycleConsumerIndex < appIPCStartIndex)
        #expect(ipcBootSource.contains("import AgentStudioAppIPC"))
        #expect(ipcBootSource.contains("import AgentStudioProgrammaticControl"))
        #expect(ipcBootSource.contains("AgentStudioIPCContributionRegistry.phaseAComposition()"))
        #expect(ipcBootSource.contains("methodContributions: ipcComposition.methodContributions"))
        #expect(ipcBootSource.contains("let rootDirectory = AppDataPaths.rootDirectory()"))
        #expect(ipcBootSource.contains("socketDirectory: Self.appIPCSocketDirectory()"))
        #expect(ipcBootSource.contains("ProcessInfo.processInfo.environment[\"AGENTSTUDIO_IPC_SOCKET_DIR\"]"))
        #expect(ipcBootSource.contains("makePaneFocusAppControl(store: store)"))
        #expect(ipcBootSource.contains("server.start()"))
        #expect(appIPCStopIndex < flushStoresIndex)
        #expect(mainWindowControllerSource.contains("makePaneFocusAppControl(store: WorkspaceStore)"))
        #expect(splitViewControllerSource.contains("makePaneFocusAppControl(store: WorkspaceStore)"))
        #expect(splitViewControllerSource.contains("PaneTabViewControllerPaneFocusAppControl"))
    }
}
