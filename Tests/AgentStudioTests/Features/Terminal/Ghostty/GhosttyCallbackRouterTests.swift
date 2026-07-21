import AppKit
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("Ghostty callback router")
struct GhosttyCallbackRouterTests {
    @Test("readClipboard returns false when no surface userdata is available")
    func readClipboard_withoutUserdata_returnsFalse() {
        let handled = Ghostty.CallbackRouter.readClipboard(
            nil,
            location: GHOSTTY_CLIPBOARD_STANDARD,
            state: nil
        )

        #expect(!handled)
    }

    @Test("runtimeConfig read clipboard callback can invoke the helper path")
    func runtimeConfig_readClipboardCallback_invokesHelperPath() {
        let userdataPointer = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let config = Ghostty.CallbackRouter.runtimeConfig(userdataPointer: userdataPointer)

        let handled = config.read_clipboard_cb(nil, GHOSTTY_CLIPBOARD_STANDARD, nil)

        #expect(!handled)
    }

    @Test("runtimeConfig action callback copies borrowed title before returning handled result")
    func runtimeConfig_actionCallback_copiesBorrowedTitleBeforeReturningHandledResult() throws {
        let initializationStatus = GhosttyLaunchArguments.withUnsafeArgv(from: ["AgentStudioTests"]) { argc, argv in
            ghostty_init(argc, argv)
        }
        try #require(initializationStatus == GHOSTTY_SUCCESS)
        _ = NSApplication.shared

        let app = Ghostty.App()
        let appHandle = try #require(app.app)
        let surfaceID = UUIDv7.generate()
        let surfaceView = Ghostty.SurfaceView(
            app: app,
            managedSurfaceID: surfaceID,
            config: Ghostty.SurfaceConfiguration(
                startupStrategy: .surfaceCommand("/usr/bin/true"),
                initialFrame: NSRect(x: 0, y: 0, width: 640, height: 480)
            )
        )
        let surfaceHandle = try #require(surfaceView.surface)
        defer {
            Ghostty.ActionRouter.retireLocalActions(for: surfaceID)
        }

        let runtimeConfig = Ghostty.CallbackRouter.runtimeConfig(
            userdataPointer: Unmanaged.passUnretained(app).toOpaque()
        )
        let target = ghostty_target_s(
            tag: GHOSTTY_TARGET_SURFACE,
            target: ghostty_target_u(surface: surfaceHandle)
        )
        let originalTitle = "callback-owned-title"
        var borrowedTitle = Array(originalTitle.utf8CString)

        let handled = borrowedTitle.withUnsafeMutableBufferPointer { titleBuffer in
            let action = ghostty_action_s(
                tag: GHOSTTY_ACTION_SET_TITLE,
                action: ghostty_action_u(
                    set_title: ghostty_action_set_title_s(title: titleBuffer.baseAddress)
                )
            )
            let handled = runtimeConfig.action_cb(appHandle, target, action)
            titleBuffer[0] = 88
            return handled
        }

        #expect(handled)
        let retainedTitle = try #require(
            Ghostty.ActionRouter.localActionAccumulator.detachTitleBeforeExactBarrier(for: surfaceID)
        )
        #expect(retainedTitle.metadata.runtimeTitle == .titleChanged(originalTitle))
        #expect(retainedTitle.metadata.surfaceTitle == originalTitle)
    }
}
