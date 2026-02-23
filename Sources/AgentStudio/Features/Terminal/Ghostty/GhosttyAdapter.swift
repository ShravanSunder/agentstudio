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
        case .newTab:
            return .newTab
        case .closeTab:
            guard
                case .closeTab(let modeRawValue) = payload,
                let mode = closeTabMode(from: modeRawValue)
            else {
                return .unhandled(tag: actionTag.rawValue)
            }
            return .closeTab(mode: mode)
        case .gotoTab:
            guard
                case .gotoTab(let targetRawValue) = payload,
                let target = gotoTabTarget(from: targetRawValue)
            else {
                return .unhandled(tag: actionTag.rawValue)
            }
            return .gotoTab(target: target)
        case .moveTab:
            guard case .moveTab(let amount) = payload else {
                return .unhandled(tag: actionTag.rawValue)
            }
            return .moveTab(amount: amount)
        case .newSplit:
            guard
                case .newSplit(let directionRawValue) = payload,
                let direction = splitDirection(from: directionRawValue)
            else {
                return .unhandled(tag: actionTag.rawValue)
            }
            return .newSplit(direction: direction)
        case .gotoSplit:
            guard
                case .gotoSplit(let directionRawValue) = payload,
                let direction = gotoSplitDirection(from: directionRawValue)
            else {
                return .unhandled(tag: actionTag.rawValue)
            }
            return .gotoSplit(direction: direction)
        case .resizeSplit:
            guard
                case .resizeSplit(let amount, let directionRawValue) = payload,
                let direction = resizeSplitDirection(from: directionRawValue)
            else {
                return .unhandled(tag: actionTag.rawValue)
            }
            return .resizeSplit(amount: amount, direction: direction)
        case .equalizeSplits:
            return .equalizeSplits
        case .toggleSplitZoom:
            return .toggleSplitZoom
        case .quit, .newWindow, .setTitle, .pwd, .closeAllWindows, .toggleMaximize, .toggleFullscreen,
            .toggleTabOverview, .toggleWindowDecorations, .toggleQuickTerminal, .toggleCommandPalette,
            .toggleVisibility, .toggleBackgroundOpacity, .gotoWindow, .presentTerminal, .sizeLimit,
            .resetWindowSize, .initialSize, .cellSize, .scrollbar, .render, .inspector, .showGtkInspector,
            .renderInspector, .desktopNotification, .promptTitle, .mouseShape, .mouseVisibility, .mouseOverLink,
            .rendererHealth, .openConfig, .quitTimer, .floatWindow, .secureInput, .keySequence, .keyTable,
            .colorChange, .reloadConfig, .configChange, .closeWindow, .undo, .redo, .checkForUpdates, .openURL,
            .showChildExited, .progressReport, .showOnScreenKeyboard, .commandFinished, .startSearch, .endSearch,
            .searchTotal, .searchSelected, .readOnly, .copyTitleToClipboard:
            return .unhandled(tag: actionTag.rawValue)
        }
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
}
