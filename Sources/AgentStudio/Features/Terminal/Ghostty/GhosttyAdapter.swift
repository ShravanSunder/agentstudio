import AppKit
import Foundation
import GhosttyKit
import os.log

private let ghosttyAdapterLogger = Logger(subsystem: "com.agentstudio", category: "GhosttyAdapter")

/// Adapter boundary translating low-level Ghostty action tags into typed
/// domain events consumed by TerminalRuntime.
@MainActor
final class GhosttyAdapter {
    private static let deferredTags: Set<GhosttyActionTag> = [
        .setTabTitle,
        .scrollbar,
        .render,
        .mouseShape,
        .mouseVisibility,
        .mouseOverLink,
        .keySequence,
        .keyTable,
        .colorChange,
        .reloadConfig,
        .configChange,
        .startSearch,
        .endSearch,
        .searchTotal,
        .searchSelected,
    ]

    private static let interceptOnlyTags: Set<GhosttyActionTag> = [
        .quit,
        .newWindow,
        .closeAllWindows,
        .toggleMaximize,
        .toggleFullscreen,
        .toggleTabOverview,
        .toggleWindowDecorations,
        .toggleQuickTerminal,
        .toggleCommandPalette,
        .toggleVisibility,
        .toggleBackgroundOpacity,
        .gotoWindow,
        .presentTerminal,
        .resetWindowSize,
        .inspector,
        .showGtkInspector,
        .renderInspector,
        .openConfig,
        .quitTimer,
        .floatWindow,
        .closeWindow,
        .checkForUpdates,
        .showChildExited,
        .showOnScreenKeyboard,
    ]

    enum ActionPayload: Sendable, Equatable {
        case noPayload
        case titleChanged(String)
        case cwdChanged(String)
        case commandFinished(exitCode: Int, duration: UInt64)
        case closeTab(modeRawValue: UInt32)
        case gotoTab(targetRawValue: Int32)
        case moveTab(amount: Int)
        case newSplit(directionRawValue: UInt32)
        case gotoSplit(directionRawValue: UInt32)
        case resizeSplit(amount: UInt16, directionRawValue: UInt32)
        case progressReport(stateRawValue: UInt32, progress: Int8)
        case readOnly(modeRawValue: UInt32)
        case secureInput(modeRawValue: UInt32)
        case rendererHealth(rawValue: UInt32)
        case cellSizeChanged(width: UInt32, height: UInt32)
        case initialSizeChanged(width: UInt32, height: UInt32)
        case sizeLimitChanged(minWidth: UInt32, minHeight: UInt32, maxWidth: UInt32, maxHeight: UInt32)
        case promptTitle(scopeRawValue: UInt32)
        case desktopNotification(title: String, body: String)
        case openURL(url: String, kindRawValue: UInt32)
    }

    static let shared = GhosttyAdapter()

    private init() {}

    func translate(
        actionTag: UInt32,
        payload: ActionPayload = .noPayload
    ) -> GhosttyEvent {
        guard let knownActionTag = GhosttyActionTag(rawValue: actionTag) else {
            return .unhandled(tag: actionTag)
        }
        return translate(actionTag: knownActionTag, payload: payload)
    }

    func translate(
        actionTag: GhosttyActionTag,
        payload: ActionPayload = .noPayload
    ) -> GhosttyEvent {
        if Self.deferredTags.contains(actionTag) {
            return .deferred(tag: actionTag.rawValue)
        }

        if Self.interceptOnlyTags.contains(actionTag) {
            return .unhandled(tag: actionTag.rawValue)
        }

        if let coreEvent = translateCoreAction(actionTag: actionTag, payload: payload) {
            return coreEvent
        }

        if let observedEvent = translateObservedAction(actionTag: actionTag, payload: payload) {
            return observedEvent
        }

        preconditionFailure("translate(actionTag:) missing routed case for \(actionTag)")
    }

    func route(
        actionTag: UInt32,
        payload: ActionPayload = .noPayload,
        to runtime: TerminalRuntime
    ) {
        let event = translate(actionTag: actionTag, payload: payload)
        if case .unhandled(let unhandledTag) = event {
            ghosttyAdapterLogger.warning(
                "Unhandled Ghostty action tag \(unhandledTag) payload=\(String(describing: payload), privacy: .public)"
            )
        }
        runtime.handleGhosttyEvent(event)
    }

    private func translateSetTitle(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .titleChanged(let title) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".titleChanged(String)"
            )
        }
        return .titleChanged(title)
    }

    private func translatePwd(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .cwdChanged(let cwdPath) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".cwdChanged(String)"
            )
        }
        return .cwdChanged(cwdPath)
    }

    private func translateCommandFinished(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .commandFinished(let exitCode, let duration) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".commandFinished(exitCode: Int, duration: UInt64)"
            )
        }
        return .commandFinished(exitCode: exitCode, duration: duration)
    }

    private func translateCloseTab(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard
            case .closeTab(let modeRawValue) = payload,
            let mode = closeTabMode(from: modeRawValue)
        else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".closeTab(modeRawValue: UInt32)"
            )
        }
        return .closeTab(mode: mode)
    }

    private func translateGotoTab(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard
            case .gotoTab(let targetRawValue) = payload,
            let target = gotoTabTarget(from: targetRawValue)
        else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".gotoTab(targetRawValue: Int32)"
            )
        }
        return .gotoTab(target: target)
    }

    private func translateMoveTab(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .moveTab(let amount) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".moveTab(amount: Int)"
            )
        }
        return .moveTab(amount: amount)
    }

    private func translateNewSplit(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard
            case .newSplit(let directionRawValue) = payload,
            let direction = splitDirection(from: directionRawValue)
        else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".newSplit(directionRawValue: UInt32)"
            )
        }
        return .newSplit(direction: direction)
    }

    private func translateGotoSplit(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard
            case .gotoSplit(let directionRawValue) = payload,
            let direction = gotoSplitDirection(from: directionRawValue)
        else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".gotoSplit(directionRawValue: UInt32)"
            )
        }
        return .gotoSplit(direction: direction)
    }

    private func translateResizeSplit(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard
            case .resizeSplit(let amount, let directionRawValue) = payload,
            let direction = resizeSplitDirection(from: directionRawValue)
        else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".resizeSplit(amount: UInt16, directionRawValue: UInt32)"
            )
        }
        return .resizeSplit(amount: amount, direction: direction)
    }

    private func translateProgressReport(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .progressReport(let stateRawValue, let progress) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".progressReport(stateRawValue: UInt32, progress: Int8)"
            )
        }

        switch stateRawValue {
        case UInt32(truncatingIfNeeded: GHOSTTY_PROGRESS_STATE_REMOVE.rawValue):
            return .progressReportUpdated(nil)
        case UInt32(truncatingIfNeeded: GHOSTTY_PROGRESS_STATE_SET.rawValue):
            return .progressReportUpdated(ProgressState(kind: .set, percent: progressPercent(progress)))
        case UInt32(truncatingIfNeeded: GHOSTTY_PROGRESS_STATE_ERROR.rawValue):
            return .progressReportUpdated(ProgressState(kind: .error, percent: progressPercent(progress)))
        case UInt32(truncatingIfNeeded: GHOSTTY_PROGRESS_STATE_INDETERMINATE.rawValue):
            return .progressReportUpdated(
                ProgressState(kind: .indeterminate, percent: progressPercent(progress))
            )
        case UInt32(truncatingIfNeeded: GHOSTTY_PROGRESS_STATE_PAUSE.rawValue):
            return .progressReportUpdated(ProgressState(kind: .paused, percent: progressPercent(progress)))
        default:
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: "known progress report state"
            )
        }
    }

    private func translateCoreAction(
        actionTag: GhosttyActionTag,
        payload: ActionPayload
    ) -> GhosttyEvent? {
        switch actionTag {
        case .ringBell:
            return .bellRang
        case .setTitle:
            return translateSetTitle(payload: payload, actionTag: actionTag)
        case .pwd:
            return translatePwd(payload: payload, actionTag: actionTag)
        case .commandFinished:
            return translateCommandFinished(payload: payload, actionTag: actionTag)
        case .newTab:
            return .newTab
        case .closeTab:
            return translateCloseTab(payload: payload, actionTag: actionTag)
        case .gotoTab:
            return translateGotoTab(payload: payload, actionTag: actionTag)
        case .moveTab:
            return translateMoveTab(payload: payload, actionTag: actionTag)
        case .newSplit:
            return translateNewSplit(payload: payload, actionTag: actionTag)
        case .gotoSplit:
            return translateGotoSplit(payload: payload, actionTag: actionTag)
        case .resizeSplit:
            return translateResizeSplit(payload: payload, actionTag: actionTag)
        case .equalizeSplits:
            return .equalizeSplits
        case .toggleSplitZoom:
            return .toggleSplitZoom
        default:
            return nil
        }
    }

    private func translateObservedAction(
        actionTag: GhosttyActionTag,
        payload: ActionPayload
    ) -> GhosttyEvent? {
        switch actionTag {
        case .sizeLimit:
            return translateSizeLimit(payload: payload, actionTag: actionTag)
        case .initialSize:
            return translateInitialSize(payload: payload, actionTag: actionTag)
        case .cellSize:
            return translateCellSize(payload: payload, actionTag: actionTag)
        case .desktopNotification:
            return translateDesktopNotification(payload: payload, actionTag: actionTag)
        case .promptTitle:
            return translatePromptTitle(payload: payload, actionTag: actionTag)
        case .rendererHealth:
            return translateRendererHealth(payload: payload, actionTag: actionTag)
        case .secureInput:
            return translateSecureInput(payload: payload, actionTag: actionTag)
        case .openURL:
            return translateOpenURL(payload: payload, actionTag: actionTag)
        case .progressReport:
            return translateProgressReport(payload: payload, actionTag: actionTag)
        case .readOnly:
            return translateReadOnly(payload: payload, actionTag: actionTag)
        case .undo:
            return .undoRequested
        case .redo:
            return .redoRequested
        case .copyTitleToClipboard:
            return .copyTitleToClipboardRequested
        default:
            return nil
        }
    }

    private func translateReadOnly(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .readOnly(let modeRawValue) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".readOnly(modeRawValue: UInt32)"
            )
        }

        switch modeRawValue {
        case UInt32(truncatingIfNeeded: GHOSTTY_READONLY_OFF.rawValue):
            return .readOnlyChanged(false)
        case UInt32(truncatingIfNeeded: GHOSTTY_READONLY_ON.rawValue):
            return .readOnlyChanged(true)
        default:
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: "known readonly mode"
            )
        }
    }

    private func translateSecureInput(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .secureInput(let modeRawValue) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".secureInput(modeRawValue: UInt32)"
            )
        }

        switch modeRawValue {
        case UInt32(truncatingIfNeeded: GHOSTTY_SECURE_INPUT_ON.rawValue):
            return .secureInputRequested(.on)
        case UInt32(truncatingIfNeeded: GHOSTTY_SECURE_INPUT_OFF.rawValue):
            return .secureInputRequested(.off)
        case UInt32(truncatingIfNeeded: GHOSTTY_SECURE_INPUT_TOGGLE.rawValue):
            return .secureInputRequested(.toggle)
        default:
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: "known secure input mode"
            )
        }
    }

    private func translateRendererHealth(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .rendererHealth(let rawValue) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".rendererHealth(rawValue: UInt32)"
            )
        }

        switch rawValue {
        case UInt32(truncatingIfNeeded: GHOSTTY_RENDERER_HEALTH_HEALTHY.rawValue):
            return .rendererHealthChanged(healthy: true)
        case UInt32(truncatingIfNeeded: GHOSTTY_RENDERER_HEALTH_UNHEALTHY.rawValue):
            return .rendererHealthChanged(healthy: false)
        default:
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: "known renderer health value"
            )
        }
    }

    private func translateCellSize(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .cellSizeChanged(let width, let height) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".cellSizeChanged(width: UInt32, height: UInt32)"
            )
        }

        return .cellSizeChanged(
            NSSize(width: Double(width), height: Double(height))
        )
    }

    private func translateInitialSize(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .initialSizeChanged(let width, let height) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".initialSizeChanged(width: UInt32, height: UInt32)"
            )
        }

        return .initialSizeChanged(
            NSSize(width: Double(width), height: Double(height))
        )
    }

    private func translateSizeLimit(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .sizeLimitChanged(let minWidth, let minHeight, let maxWidth, let maxHeight) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload:
                    ".sizeLimitChanged(minWidth: UInt32, minHeight: UInt32, maxWidth: UInt32, maxHeight: UInt32)"
            )
        }

        return .sizeLimitChanged(
            TerminalSizeConstraints(
                minWidth: minWidth,
                minHeight: minHeight,
                maxWidth: maxWidth,
                maxHeight: maxHeight
            )
        )
    }

    private func translatePromptTitle(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .promptTitle(let scopeRawValue) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".promptTitle(scopeRawValue: UInt32)"
            )
        }

        switch scopeRawValue {
        case UInt32(truncatingIfNeeded: GHOSTTY_PROMPT_TITLE_SURFACE.rawValue):
            return .promptTitleRequested(scope: .surface)
        case UInt32(truncatingIfNeeded: GHOSTTY_PROMPT_TITLE_TAB.rawValue):
            return .promptTitleRequested(scope: .tab)
        default:
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: "known prompt title scope"
            )
        }
    }

    private func translateDesktopNotification(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .desktopNotification(let title, let body) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".desktopNotification(title: String, body: String)"
            )
        }

        return .desktopNotificationRequested(title: title, body: body)
    }

    private func translateOpenURL(payload: ActionPayload, actionTag: GhosttyActionTag) -> GhosttyEvent {
        guard case .openURL(let url, let kindRawValue) = payload else {
            return payloadMismatch(
                actionTag: actionTag,
                payload: payload,
                expectedPayload: ".openURL(url: String, kindRawValue: UInt32)"
            )
        }

        let kind: OpenURLKind =
            switch kindRawValue {
            case UInt32(truncatingIfNeeded: GHOSTTY_ACTION_OPEN_URL_KIND_TEXT.rawValue):
                .text
            case UInt32(truncatingIfNeeded: GHOSTTY_ACTION_OPEN_URL_KIND_HTML.rawValue):
                .html
            default:
                .unknown
            }

        return .openURLRequested(url: url, kind: kind)
    }

    private func closeTabMode(from rawValue: UInt32) -> GhosttyCloseTabMode? {
        switch rawValue {
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS.rawValue:
            return .thisTab
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER.rawValue:
            return .otherTabs
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT.rawValue:
            return .rightTabs
        default:
            return nil
        }
    }

    private func gotoTabTarget(from rawValue: Int32) -> GhosttyGotoTabTarget? {
        switch rawValue {
        case GHOSTTY_GOTO_TAB_PREVIOUS.rawValue:
            return .previous
        case GHOSTTY_GOTO_TAB_NEXT.rawValue:
            return .next
        case GHOSTTY_GOTO_TAB_LAST.rawValue:
            return .last
        default:
            guard rawValue >= 1 else { return nil }
            return .index(Int(rawValue))
        }
    }

    private func splitDirection(from rawValue: UInt32) -> GhosttySplitDirection? {
        switch rawValue {
        case GHOSTTY_SPLIT_DIRECTION_LEFT.rawValue:
            return .left
        case GHOSTTY_SPLIT_DIRECTION_RIGHT.rawValue:
            return .right
        case GHOSTTY_SPLIT_DIRECTION_UP.rawValue:
            return .up
        case GHOSTTY_SPLIT_DIRECTION_DOWN.rawValue:
            return .down
        default:
            return nil
        }
    }

    private func gotoSplitDirection(from rawValue: UInt32) -> GhosttyGotoSplitDirection? {
        switch rawValue {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS.rawValue:
            return .previous
        case GHOSTTY_GOTO_SPLIT_NEXT.rawValue:
            return .next
        case GHOSTTY_GOTO_SPLIT_LEFT.rawValue:
            return .left
        case GHOSTTY_GOTO_SPLIT_RIGHT.rawValue:
            return .right
        case GHOSTTY_GOTO_SPLIT_UP.rawValue:
            return .up
        case GHOSTTY_GOTO_SPLIT_DOWN.rawValue:
            return .down
        default:
            return nil
        }
    }

    private func resizeSplitDirection(from rawValue: UInt32) -> GhosttyResizeSplitDirection? {
        switch rawValue {
        case GHOSTTY_RESIZE_SPLIT_LEFT.rawValue:
            return .left
        case GHOSTTY_RESIZE_SPLIT_RIGHT.rawValue:
            return .right
        case GHOSTTY_RESIZE_SPLIT_UP.rawValue:
            return .up
        case GHOSTTY_RESIZE_SPLIT_DOWN.rawValue:
            return .down
        default:
            return nil
        }
    }

    private func progressPercent(_ rawProgress: Int8) -> UInt8? {
        rawProgress >= 0 ? UInt8(rawProgress) : nil
    }

    private func payloadMismatch(
        actionTag: GhosttyActionTag,
        payload: ActionPayload,
        expectedPayload: String
    ) -> GhosttyEvent {
        ghosttyAdapterLogger.warning(
            "Ghostty payload mismatch for action tag \(actionTag.rawValue, privacy: .public): expected \(expectedPayload, privacy: .public), got \(String(describing: payload), privacy: .public)"
        )
        return .unhandled(tag: actionTag.rawValue)
    }
}
