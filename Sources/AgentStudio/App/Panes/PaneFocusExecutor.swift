import AppKit
import Foundation
import os

@MainActor
final class PaneFocusExecutor {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "PaneFocusExecutor")
    typealias HostViewProvider = @MainActor (UUID) -> PaneHostView?
    typealias HostViewsProvider = @MainActor () -> [PaneHostView]
    typealias TabSelectionHandler = @MainActor (UUID) -> Void
    typealias PaneSelectionHandler = @MainActor (UUID, UUID) -> Void
    typealias DrawerSelectionHandler = @MainActor (UUID, UUID) -> Void
    typealias DrawerEmptySelectionHandler = @MainActor (UUID) -> Void
    typealias RuntimeFocusHandler = @MainActor (UUID?) -> Void

    private var registeredHostViewsByPaneId: [UUID: PaneHostView] = [:]

    private let hostViewProvider: HostViewProvider
    private let hostViewsProvider: HostViewsProvider
    private let selectTab: TabSelectionHandler
    private let selectPane: PaneSelectionHandler
    private let selectDrawerPane: DrawerSelectionHandler
    private let selectEmptyDrawer: DrawerEmptySelectionHandler
    private let syncRuntimeFocus: RuntimeFocusHandler

    init(
        hostViewProvider: @escaping HostViewProvider,
        hostViewsProvider: @escaping HostViewsProvider,
        selectTab: @escaping TabSelectionHandler,
        selectPane: @escaping PaneSelectionHandler,
        selectDrawerPane: @escaping DrawerSelectionHandler,
        selectEmptyDrawer: @escaping DrawerEmptySelectionHandler,
        syncRuntimeFocus: @escaping RuntimeFocusHandler
    ) {
        self.hostViewProvider = hostViewProvider
        self.hostViewsProvider = hostViewsProvider
        self.selectTab = selectTab
        self.selectPane = selectPane
        self.selectDrawerPane = selectDrawerPane
        self.selectEmptyDrawer = selectEmptyDrawer
        self.syncRuntimeFocus = syncRuntimeFocus
    }

    func registerHostView(_ view: PaneHostView) {
        registeredHostViewsByPaneId[view.paneId] = view
    }

    func unregisterHostView(_ paneId: UUID) {
        registeredHostViewsByPaneId.removeValue(forKey: paneId)
    }

    @discardableResult
    func apply(_ decision: PaneFocusDecision) -> Bool {
        switch decision {
        case .noOp:
            return true
        case .contentClick(let decision):
            applySelection(decision.selection)
            applyContent(decision.content)
            let didApplyResponder = applyResponder(decision.responder)
            applyRuntime(decision.runtime)
            return didApplyResponder
        case .tabClick(let decision):
            applySelection(decision.selection)
            let didApplyResponder = applyResponder(decision.responder)
            applyRuntime(decision.runtime)
            return didApplyResponder
        case .drawer(let decision):
            applySelection(decision.selection)
            let didApplyResponder = applyResponder(decision.responder)
            applyRuntime(decision.runtime)
            return didApplyResponder
        case .keyboard(let decision):
            applySelection(decision.selection)
            let didApplyResponder = applyResponder(decision.responder)
            applyRuntime(decision.runtime)
            return didApplyResponder
        case .mode(let decision):
            applyContent(decision.content)
            return applyResponder(decision.responder)
        case .refocusRequest(let decision):
            let didApplyResponder = applyResponder(decision.responder)
            applyRuntime(decision.runtime)
            return didApplyResponder
        case .command(let decision):
            applySelection(decision.selection)
            let didApplyResponder = applyResponder(decision.responder)
            applyRuntime(decision.runtime)
            return didApplyResponder
        }
    }

    private func hostView(for paneId: UUID) -> PaneHostView? {
        registeredHostViewsByPaneId[paneId] ?? hostViewProvider(paneId)
    }

    private func allHostViews() -> [PaneHostView] {
        var hostViewsByPaneId = registeredHostViewsByPaneId
        for hostView in hostViewsProvider() {
            hostViewsByPaneId[hostView.paneId] = hostView
        }
        return Array(hostViewsByPaneId.values)
    }

    private func applySelection(_ selection: PaneContentClickSelectionAction) {
        switch selection {
        case .keep:
            return
        case .selectPane(let tabId, let paneId):
            selectPane(tabId, paneId)
        }
    }

    private func applySelection(_ selection: PaneTabClickSelectionAction) {
        switch selection {
        case .selectTab(let tabId):
            selectTab(tabId)
        }
    }

    private func applySelection(_ selection: PaneDrawerSelectionAction) {
        switch selection {
        case .keep:
            return
        case .selectDrawerPane(let parentPaneId, let drawerPaneId):
            selectDrawerPane(parentPaneId, drawerPaneId)
        }
    }

    private func applySelection(_ selection: PaneKeyboardSelectionAction) {
        switch selection {
        case .selectPane(let tabId, let paneId):
            selectPane(tabId, paneId)
        }
    }

    private func applySelection(_ selection: PaneCommandSelectionAction) {
        switch selection {
        case .keep:
            return
        case .selectPane(let tabId, let paneId):
            selectPane(tabId, paneId)
        case .selectTab(let tabId):
            selectTab(tabId)
        }
    }

    private func applyContent(_ action: PaneContentClickOwnershipAction) {
        switch action {
        case .preserve:
            return
        }
    }

    private func applyContent(_ action: PaneModeContentAction) {
        let isEnabled: Bool
        switch action {
        case .block:
            isEnabled = false
        case .release:
            isEnabled = true
        }

        for hostView in allHostViews() {
            hostView.setContentInteractionEnabled(isEnabled)
        }
    }

    private func applyResponder(_ action: PaneContentClickResponderAction) -> Bool {
        switch action {
        case .preserveCurrentResponder:
            return true
        case .focusPaneHost(let paneId):
            return focusPaneHostIfReady(paneId)
        }
    }

    private func applyResponder(_ action: PaneTabClickResponderAction) -> Bool {
        switch action {
        case .preserveCurrentResponder:
            return true
        }
    }

    private func applyResponder(_ action: PaneDrawerResponderAction) -> Bool {
        switch action {
        case .preserveCurrentResponder:
            return true
        case .focusPaneHost(let paneId):
            return focusPaneHostIfReady(paneId)
        }
    }

    private func applyResponder(_ action: PaneKeyboardResponderAction) -> Bool {
        switch action {
        case .preserveCurrentResponder:
            return true
        case .focusPaneHost(let paneId):
            return focusPaneHostIfReady(paneId)
        }
    }

    private func applyResponder(_ action: PaneModeResponderAction) -> Bool {
        switch action {
        case .preserveCurrentResponder:
            return true
        case .clearToWindowContent:
            return clearFirstResponderToWindowContent()
        }
    }

    private func applyResponder(_ action: PaneRefocusRequestResponderAction) -> Bool {
        switch action {
        case .preserveCurrentResponder:
            return true
        case .focusPaneHost(let paneId):
            return focusPaneHostIfReady(paneId)
        case .focusMountedContent(let paneId):
            return focusMountedContentIfReady(paneId)
        }
    }

    private func applyResponder(_ action: PaneCommandResponderAction) -> Bool {
        switch action {
        case .preserveCurrentResponder:
            return true
        case .focusPaneHost(let paneId):
            return focusPaneHostIfReady(paneId)
        }
    }

    private func applyRuntime(_ action: PaneContentClickRuntimeAction) {
        switch action {
        case .preserveRuntimeFocus:
            return
        case .syncTerminalSurface(let paneId):
            syncTerminalRuntimeFocus(for: paneId)
        }
    }

    private func applyRuntime(_ action: PaneTabClickRuntimeAction) {
        switch action {
        case .preserveRuntimeFocus:
            return
        }
    }

    private func applyRuntime(_ action: PaneDrawerRuntimeAction) {
        switch action {
        case .preserveRuntimeFocus:
            return
        }
    }

    private func applyRuntime(_ action: PaneKeyboardRuntimeAction) {
        switch action {
        case .preserveRuntimeFocus:
            return
        case .syncTerminalSurface(let paneId):
            syncTerminalRuntimeFocus(for: paneId)
        }
    }

    private func applyRuntime(_ action: PaneRefocusRequestRuntimeAction) {
        switch action {
        case .preserveRuntimeFocus:
            return
        case .syncTerminalSurface(let paneId):
            syncTerminalRuntimeFocus(for: paneId)
        }
    }

    private func applyRuntime(_ action: PaneCommandRuntimeAction) {
        switch action {
        case .preserveRuntimeFocus:
            return
        case .syncTerminalSurface(let paneId):
            syncTerminalRuntimeFocus(for: paneId)
        }
    }

    @discardableResult
    private func focusPaneHostIfReady(_ paneId: UUID) -> Bool {
        guard let hostView = hostView(for: paneId), let window = hostView.window else {
            Self.logger.warning(
                "focusPaneHostIfReady skipped pane=\(paneId.uuidString, privacy: .public) reason=hostOrWindowMissing")
            return false
        }
        let targetResponder = hostView.preferredFirstResponderViewForPaneFocus ?? hostView
        let didFocus = window.makeFirstResponder(targetResponder)
        if !didFocus {
            Self.logger.warning("focusPaneHostIfReady failed pane=\(paneId.uuidString, privacy: .public)")
        }
        return didFocus
    }

    @discardableResult
    private func focusMountedContentIfReady(_ paneId: UUID) -> Bool {
        guard
            let hostView = hostView(for: paneId),
            let window = hostView.window,
            let mountedContentView = hostView.mountedContentView,
            mountedContentView.acceptsFirstResponder
        else {
            Self.logger.warning(
                "focusMountedContentIfReady skipped pane=\(paneId.uuidString, privacy: .public) reason=mountedContentUnavailable"
            )
            return false
        }

        let didFocus = window.makeFirstResponder(mountedContentView)
        if !didFocus {
            Self.logger.warning("focusMountedContentIfReady failed pane=\(paneId.uuidString, privacy: .public)")
        }
        return didFocus
    }

    @discardableResult
    private func clearFirstResponderToWindowContent() -> Bool {
        guard
            let window = allHostViews().compactMap(\.window).first ?? NSApp.keyWindow,
            let contentView = window.contentView
        else {
            Self.logger.warning("clearFirstResponderToWindowContent skipped reason=noWindow")
            return false
        }

        let didFocus = window.makeFirstResponder(contentView)
        if !didFocus {
            Self.logger.warning("clearFirstResponderToWindowContent failed")
        }
        return didFocus
    }

    private func syncTerminalRuntimeFocus(for paneId: UUID) {
        let surfaceId = hostView(for: paneId)?.mountedTerminalSurfaceId
        if surfaceId == nil {
            Self.logger.warning("syncTerminalRuntimeFocus nilSurface pane=\(paneId.uuidString, privacy: .public)")
            return
        }
        syncRuntimeFocus(surfaceId)
    }
}
