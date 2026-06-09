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

    @Test("startup diagnostic trigger is opt in and routes through CommandDispatcher")
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
        #expect(startupDiagnosticsSource.contains("AgentStudioStartupDiagnosticAction.fromEnvironment()"))
        #expect(startupDiagnosticsSource.contains("CommandDispatcher.shared.dispatch(.newTab)"))
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
}
