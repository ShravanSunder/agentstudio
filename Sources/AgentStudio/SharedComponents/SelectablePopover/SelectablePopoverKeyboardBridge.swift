import AppKit
import SwiftUI

struct SelectablePopoverKeyboardBridge<ItemID: Hashable>: NSViewRepresentable {
    let items: [SelectablePopoverKeyboardItem<ItemID>]
    let selectedItemId: ItemID?
    let auxiliaryKey: String?
    let onSelect: (ItemID) -> Void
    let onAuxiliary: (ItemID) -> Void
    let onHighlight: (ItemID) -> Void
    let onDismiss: () -> Void
    let matchesAdditionalDismissShortcut: (NSEvent) -> Bool

    func makeNSView(context _: Context) -> SelectablePopoverFocusCapturingView<ItemID> {
        let view = SelectablePopoverFocusCapturingView<ItemID>()
        update(view)
        return view
    }

    func updateNSView(_ nsView: SelectablePopoverFocusCapturingView<ItemID>, context _: Context) {
        update(nsView)
        Task { @MainActor in
            guard nsView.window?.firstResponder !== nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func update(_ view: SelectablePopoverFocusCapturingView<ItemID>) {
        view.items = items
        view.selectedItemId = selectedItemId
        view.auxiliaryKey = auxiliaryKey
        view.onSelect = onSelect
        view.onAuxiliary = onAuxiliary
        view.onHighlight = onHighlight
        view.onDismiss = onDismiss
        view.matchesAdditionalDismissShortcut = matchesAdditionalDismissShortcut
    }
}

final class SelectablePopoverFocusCapturingView<ItemID: Hashable>: NSView {
    var items: [SelectablePopoverKeyboardItem<ItemID>] = []
    var selectedItemId: ItemID?
    var auxiliaryKey: String?
    var onSelect: ((ItemID) -> Void)?
    var onAuxiliary: ((ItemID) -> Void)?
    var onHighlight: ((ItemID) -> Void)?
    var onDismiss: (() -> Void)?
    var matchesAdditionalDismissShortcut: ((NSEvent) -> Bool)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            teardownMonitor()
            return
        }

        installMonitorIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        guard apply(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if apply(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
        onDismiss?()
    }

    override func moveUp(_ sender: Any?) {
        _ = sender
        highlightSelection(delta: -1)
    }

    override func moveDown(_ sender: Any?) {
        _ = sender
        highlightSelection(delta: 1)
    }

    override func insertNewline(_ sender: Any?) {
        _ = sender
        activateCurrentSelection()
    }

    private func apply(_ event: NSEvent) -> Bool {
        switch SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: selectedItemId,
            auxiliaryKey: auxiliaryKey,
            matchesAdditionalDismissShortcut: matchesAdditionalDismissShortcut ?? { _ in false }
        ) {
        case .dismiss:
            onDismiss?()
        case .select(let itemId):
            onSelect?(itemId)
        case .auxiliary(let itemId):
            onAuxiliary?(itemId)
        case .highlight(let itemId):
            onHighlight?(itemId)
        case .consume:
            return true
        case .passthrough:
            return false
        }

        return true
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.eventBelongsToThisPopover(event) else { return event }
            return self.apply(event) ? nil : event
        }
    }

    private func teardownMonitor() {
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
    }

    private func eventBelongsToThisPopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = window else { return false }

        if let eventWindow = event.window {
            return eventWindow == popoverWindow
                || eventWindow.parent == popoverWindow
                || popoverWindow.parent == eventWindow
        }

        if event.windowNumber != 0 {
            return event.windowNumber == popoverWindow.windowNumber
        }

        if let keyWindow = NSApp.keyWindow {
            return keyWindow == popoverWindow
                || keyWindow.parent == popoverWindow
                || popoverWindow.parent == keyWindow
        }

        return false
    }

    private func highlightSelection(delta: Int) {
        guard
            let itemId = SelectablePopoverKeyboardRouter.movedSelection(
                delta: delta,
                items: items,
                selectedItemId: selectedItemId
            )
        else {
            return
        }

        onHighlight?(itemId)
    }

    private func activateCurrentSelection() {
        guard
            let itemId = SelectablePopoverKeyboardRouter.currentSelection(
                items: items,
                selectedItemId: selectedItemId
            )
        else {
            return
        }

        onSelect?(itemId)
    }
}
