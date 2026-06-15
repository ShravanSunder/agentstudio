import Foundation
import GhosttyKit

extension Ghostty.ActionRouter {
    static func handleInterceptedAction(
        _ actionTag: GhosttyActionTag,
        rawActionTag: UInt32,
        target: ghostty_target_s,
        routingLookupProvider: @escaping GhosttyActionRoutingLookupProvider
    ) -> Bool {
        switch actionTag {
        case .quit:
            return true
        case .newWindow:
            ghosttyLogger.debug(
                "Ignoring Ghostty newWindow action because AgentStudio owns window lifecycle"
            )
            return true
        case .showChildExited:
            scheduleChildExitedStartupTrace(
                actionTag: rawActionTag,
                target: target,
                routingLookupProvider: routingLookupProvider
            )
            return true
        case .closeAllWindows, .toggleMaximize, .toggleFullscreen, .toggleTabOverview,
            .toggleWindowDecorations, .toggleQuickTerminal, .toggleCommandPalette, .toggleVisibility,
            .toggleBackgroundOpacity, .gotoWindow, .presentTerminal, .resetWindowSize, .inspector, .render,
            .showGtkInspector, .renderInspector, .openConfig, .quitTimer, .floatWindow, .closeWindow,
            .checkForUpdates, .showOnScreenKeyboard:
            return true
        default:
            preconditionFailure(
                "Ghostty action tag \(actionTag) is in interceptedTags but not handled explicitly"
            )
        }
    }
}
