import Foundation
import GhosttyKit
import os.log

private let ghosttyAdapterLogger = Logger(subsystem: "com.agentstudio", category: "GhosttyAdapter")

/// Adapter boundary translating low-level Ghostty action tags into typed
/// domain events consumed by TerminalRuntime.
@MainActor
final class GhosttyAdapter {
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
        case .quit, .newWindow, .closeAllWindows, .toggleMaximize, .toggleFullscreen,
            .toggleTabOverview, .toggleWindowDecorations, .toggleQuickTerminal, .toggleCommandPalette,
            .toggleVisibility, .toggleBackgroundOpacity, .gotoWindow, .presentTerminal, .sizeLimit,
            .resetWindowSize, .initialSize, .cellSize, .scrollbar, .render, .inspector, .showGtkInspector,
            .renderInspector, .desktopNotification, .promptTitle, .mouseShape, .mouseVisibility, .mouseOverLink,
            .rendererHealth, .openConfig, .quitTimer, .floatWindow, .secureInput, .keySequence, .keyTable,
            .colorChange, .reloadConfig, .configChange, .closeWindow, .undo, .redo, .checkForUpdates, .openURL,
            .showChildExited, .progressReport, .showOnScreenKeyboard, .startSearch, .endSearch,
            .searchTotal, .searchSelected, .readOnly, .copyTitleToClipboard:
            return .unhandled(tag: actionTag.rawValue)
        }
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
