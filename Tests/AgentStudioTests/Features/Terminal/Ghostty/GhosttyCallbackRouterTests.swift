import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("Ghostty callback router")
struct GhosttyCallbackRouterTests {
    private final class RoutedActionCapture {
        var actionTag: UInt32?
        var payload: GhosttyAdapter.ActionPayload?
        var handledResult: Bool?
    }

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

    @Test("runtimeConfig action callback copies borrowed title before invoking the typed route")
    func runtimeConfig_actionCallback_copiesBorrowedTitleBeforeInvokingTypedRoute() throws {
        let routeCapture = RoutedActionCapture()
        let appHandle = Unmanaged.passUnretained(routeCapture).toOpaque()
        let runtimeConfig = Ghostty.CallbackRouter.runtimeConfig(
            userdataPointer: appHandle,
            actionCallback: { appPtr, target, action in
                guard let appPtr else { return false }
                let routeCapture = Unmanaged<RoutedActionCapture>.fromOpaque(appPtr).takeUnretainedValue()
                return Ghostty.ActionRouter.handleAction(
                    appPtr,
                    target: target,
                    action: action,
                    routingLookupProvider: { @MainActor in SurfaceManager.shared },
                    metadataActionRouter: { actionTag, payload, _, handledResult in
                        routeCapture.actionTag = actionTag
                        routeCapture.payload = payload
                        routeCapture.handledResult = handledResult
                        return handledResult
                    }
                )
            }
        )
        let target = ghostty_target_s(
            tag: GHOSTTY_TARGET_APP,
            target: ghostty_target_u(surface: nil)
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
        #expect(routeCapture.actionTag == UInt32(GHOSTTY_ACTION_SET_TITLE.rawValue))
        #expect(try #require(routeCapture.payload) == .titleChanged(originalTitle))
        #expect(routeCapture.handledResult == true)
    }
}
