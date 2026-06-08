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
