import Foundation

enum PaneFocusDecision: Sendable, Equatable {
    case noOp(PaneFocusNoOpDecision)
    case contentClick(PaneContentClickFocusDecision)
    case tabClick(PaneTabClickFocusDecision)
    case drawer(PaneDrawerFocusDecision)
    case keyboard(PaneKeyboardFocusDecision)
    case mode(PaneModeFocusDecision)
    case refocusRequest(PaneRefocusRequestDecision)
    case command(PaneCommandFocusDecision)
}

struct PaneFocusNoOpDecision: Sendable, Equatable {
    let reason: PaneFocusReason
}

enum PaneFocusReason: Sendable, Equatable {
    case activeContentClickPreservesOwnership
    case inactivePaneRequiresSelection
    case managementLayerEntered
    case explicitRefocus
    case commandTriggeredFocus
    case drawerSelectionChanged
}

enum PaneContentClickSelectionAction: Sendable, Equatable {
    case keep
    case selectPane(tabId: UUID, paneId: UUID)
}

enum PaneContentClickResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

enum PaneContentClickRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

enum PaneContentClickOwnershipAction: Sendable, Equatable {
    case preserve
}

struct PaneContentClickFocusDecision: Sendable, Equatable {
    let selection: PaneContentClickSelectionAction
    let responder: PaneContentClickResponderAction
    let runtime: PaneContentClickRuntimeAction
    let content: PaneContentClickOwnershipAction
    let reason: PaneFocusReason
}

enum PaneTabClickSelectionAction: Sendable, Equatable {
    case selectTab(UUID)
}

enum PaneTabClickResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
}

enum PaneTabClickRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
}

struct PaneTabClickFocusDecision: Sendable, Equatable {
    let selection: PaneTabClickSelectionAction
    let responder: PaneTabClickResponderAction
    let runtime: PaneTabClickRuntimeAction
    let reason: PaneFocusReason
}

enum PaneDrawerSelectionAction: Sendable, Equatable {
    case keep
    case selectDrawerPane(parentPaneId: UUID, drawerPaneId: UUID)
}

enum PaneDrawerResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

enum PaneDrawerRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
}

struct PaneDrawerFocusDecision: Sendable, Equatable {
    let selection: PaneDrawerSelectionAction
    let responder: PaneDrawerResponderAction
    let runtime: PaneDrawerRuntimeAction
    let reason: PaneFocusReason
}

enum PaneKeyboardSelectionAction: Sendable, Equatable {
    case selectPane(tabId: UUID, paneId: UUID)
}

enum PaneKeyboardResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

enum PaneKeyboardRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

enum PaneKeyboardRoutingAction: Sendable, Equatable {
    case passThrough
    case consume
}

struct PaneKeyboardFocusDecision: Sendable, Equatable {
    let selection: PaneKeyboardSelectionAction
    let responder: PaneKeyboardResponderAction
    let runtime: PaneKeyboardRuntimeAction
    let keyboard: PaneKeyboardRoutingAction
    let reason: PaneFocusReason
}

enum PaneModeResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case clearToWindowContent
}

enum PaneModeKeyboardRoutingAction: Sendable, Equatable {
    case passThrough
    case consume
}

enum PaneModeContentAction: Sendable, Equatable {
    case block
    case release
}

struct PaneModeFocusDecision: Sendable, Equatable {
    let responder: PaneModeResponderAction
    let keyboard: PaneModeKeyboardRoutingAction
    let content: PaneModeContentAction
    let reason: PaneFocusReason
}

enum PaneRefocusRequestResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
    case focusMountedContent(paneId: UUID)
}

enum PaneRefocusRequestRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

struct PaneRefocusRequestDecision: Sendable, Equatable {
    let responder: PaneRefocusRequestResponderAction
    let runtime: PaneRefocusRequestRuntimeAction
    let reason: PaneFocusReason
}

enum PaneCommandSelectionAction: Sendable, Equatable {
    case keep
    case selectPane(tabId: UUID, paneId: UUID)
    case selectTab(UUID)
}

enum PaneCommandResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

enum PaneCommandRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

struct PaneCommandFocusDecision: Sendable, Equatable {
    let selection: PaneCommandSelectionAction
    let responder: PaneCommandResponderAction
    let runtime: PaneCommandRuntimeAction
    let reason: PaneFocusReason
}
