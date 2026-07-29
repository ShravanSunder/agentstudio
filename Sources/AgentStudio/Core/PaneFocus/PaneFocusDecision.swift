import Foundation

package enum PaneFocusDecision: Sendable, Equatable {
    case noOp(PaneFocusNoOpDecision)
    case contentClick(PaneContentClickFocusDecision)
    case tabClick(PaneTabClickFocusDecision)
    case drawer(PaneDrawerFocusDecision)
    case keyboard(PaneKeyboardFocusDecision)
    case mode(PaneModeFocusDecision)
    case refocusRequest(PaneRefocusRequestDecision)
    case command(PaneCommandFocusDecision)
}

package struct PaneFocusNoOpDecision: Sendable, Equatable {
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

package enum PaneContentClickSelectionAction: Sendable, Equatable {
    case keep
    case selectPane(tabId: UUID, paneId: UUID)
}

package enum PaneContentClickResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

package enum PaneContentClickRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

package enum PaneContentClickOwnershipAction: Sendable, Equatable {
    case preserve
}

package struct PaneContentClickFocusDecision: Sendable, Equatable {
    package let selection: PaneContentClickSelectionAction
    package let responder: PaneContentClickResponderAction
    package let runtime: PaneContentClickRuntimeAction
    package let content: PaneContentClickOwnershipAction
    let reason: PaneFocusReason
}

package enum PaneTabClickSelectionAction: Sendable, Equatable {
    case selectTab(UUID)
}

package enum PaneTabClickResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
}

package enum PaneTabClickRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
}

package struct PaneTabClickFocusDecision: Sendable, Equatable {
    package let selection: PaneTabClickSelectionAction
    package let responder: PaneTabClickResponderAction
    package let runtime: PaneTabClickRuntimeAction
    let reason: PaneFocusReason
}

package enum PaneDrawerSelectionAction: Sendable, Equatable {
    case keep
    case selectDrawerPane(parentPaneId: UUID, drawerPaneId: UUID)
}

package enum PaneDrawerResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

package enum PaneDrawerRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
}

package struct PaneDrawerFocusDecision: Sendable, Equatable {
    package let selection: PaneDrawerSelectionAction
    package let responder: PaneDrawerResponderAction
    package let runtime: PaneDrawerRuntimeAction
    let reason: PaneFocusReason
}

package enum PaneKeyboardSelectionAction: Sendable, Equatable {
    case selectPane(tabId: UUID, paneId: UUID)
}

package enum PaneKeyboardResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

package enum PaneKeyboardRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

enum PaneKeyboardRoutingAction: Sendable, Equatable {
    case passThrough
    case consume
}

package struct PaneKeyboardFocusDecision: Sendable, Equatable {
    package let selection: PaneKeyboardSelectionAction
    package let responder: PaneKeyboardResponderAction
    package let runtime: PaneKeyboardRuntimeAction
    let keyboard: PaneKeyboardRoutingAction
    let reason: PaneFocusReason
}

package enum PaneModeResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case clearToWindowContent
}

enum PaneModeKeyboardRoutingAction: Sendable, Equatable {
    case passThrough
    case consume
}

package enum PaneModeContentAction: Sendable, Equatable {
    case block
    case release
}

package struct PaneModeFocusDecision: Sendable, Equatable {
    package let responder: PaneModeResponderAction
    let keyboard: PaneModeKeyboardRoutingAction
    package let content: PaneModeContentAction
    let reason: PaneFocusReason
}

package enum PaneRefocusRequestResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
    case focusMountedContent(paneId: UUID)
}

package enum PaneRefocusRequestRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

package struct PaneRefocusRequestDecision: Sendable, Equatable {
    package let responder: PaneRefocusRequestResponderAction
    package let runtime: PaneRefocusRequestRuntimeAction
    let reason: PaneFocusReason
}

package enum PaneCommandSelectionAction: Sendable, Equatable {
    case keep
    case selectPane(tabId: UUID, paneId: UUID)
    case selectTab(UUID)
}

package enum PaneCommandResponderAction: Sendable, Equatable {
    case preserveCurrentResponder
    case focusPaneHost(paneId: UUID)
}

package enum PaneCommandRuntimeAction: Sendable, Equatable {
    case preserveRuntimeFocus
    case syncTerminalSurface(paneId: UUID)
}

package struct PaneCommandFocusDecision: Sendable, Equatable {
    package let selection: PaneCommandSelectionAction
    package let responder: PaneCommandResponderAction
    package let runtime: PaneCommandRuntimeAction
    let reason: PaneFocusReason
}
