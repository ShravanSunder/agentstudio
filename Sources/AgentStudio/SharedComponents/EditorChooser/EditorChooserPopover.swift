import AppKit
import SwiftUI

struct EditorChooserPopover: View {
    let items: [EditorChoiceItem]
    let bookmarkedEditorId: EditorTargetId?
    let directLaunchHintText: String?
    let directLaunchShortcutText: String?
    let style: EditorChooserMenuStyle
    let onSelect: (EditorTargetId) -> Void
    let onToggleBookmark: (EditorTargetId) -> Void
    let onDismiss: () -> Void
    let matchesAdditionalDismissShortcut: (NSEvent) -> Bool

    @State private var selectedEditorId: EditorTargetId?

    var body: some View {
        EditorChooserMenuContent(
            items: items,
            bookmarkedEditorId: bookmarkedEditorId,
            selectedEditorId: selectedEditorId,
            directLaunchHintText: directLaunchHintText,
            directLaunchShortcutText: directLaunchShortcutText,
            style: style,
            onSelect: onSelect,
            onToggleBookmark: onToggleBookmark
        )
        .background(
            EditorChooserKeyboardBridge(
                items: items,
                selectedEditorId: selectedEditorId,
                onSelect: { editorId in
                    selectedEditorId = editorId
                    onSelect(editorId)
                },
                onToggleBookmark: { editorId in
                    selectedEditorId = editorId
                    onToggleBookmark(editorId)
                },
                onHighlight: { editorId in
                    selectedEditorId = editorId
                },
                onDismiss: onDismiss,
                matchesAdditionalDismissShortcut: matchesAdditionalDismissShortcut
            )
            .frame(width: 0, height: 0)
        )
        .onAppear(perform: repairSelection)
        .onChange(of: itemIDs) { _, _ in repairSelection() }
        .onChange(of: bookmarkedEditorId) { _, _ in repairSelection() }
        .onExitCommand(perform: onDismiss)
    }

    private var itemIDs: [EditorTargetId] {
        items.map(\.id)
    }

    private func repairSelection() {
        if let selectedEditorId, itemIDs.contains(selectedEditorId) {
            return
        }
        selectedEditorId = EditorChooserKeyboardRouter.defaultSelection(
            items: items,
            bookmarkedEditorId: bookmarkedEditorId
        )
    }
}

private struct EditorChooserKeyboardBridge: NSViewRepresentable {
    let items: [EditorChoiceItem]
    let selectedEditorId: EditorTargetId?
    let onSelect: (EditorTargetId) -> Void
    let onToggleBookmark: (EditorTargetId) -> Void
    let onHighlight: (EditorTargetId) -> Void
    let onDismiss: () -> Void
    let matchesAdditionalDismissShortcut: (NSEvent) -> Bool

    func makeNSView(context _: Context) -> FocusCapturingView {
        let view = FocusCapturingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: FocusCapturingView, context _: Context) {
        update(nsView)
        Task { @MainActor in
            guard nsView.window?.firstResponder !== nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func update(_ view: FocusCapturingView) {
        view.items = items
        view.selectedEditorId = selectedEditorId
        view.onSelect = onSelect
        view.onToggleBookmark = onToggleBookmark
        view.onHighlight = onHighlight
        view.onDismiss = onDismiss
        view.matchesAdditionalDismissShortcut = matchesAdditionalDismissShortcut
    }
}

private final class FocusCapturingView: NSView {
    var items: [EditorChoiceItem] = []
    var selectedEditorId: EditorTargetId?
    var onSelect: ((EditorTargetId) -> Void)?
    var onToggleBookmark: ((EditorTargetId) -> Void)?
    var onHighlight: ((EditorTargetId) -> Void)?
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
        switch EditorChooserKeyboardRouter.action(
            for: event,
            items: items,
            selectedEditorId: selectedEditorId,
            matchesAdditionalDismissShortcut: matchesAdditionalDismissShortcut ?? { _ in false }
        ) {
        case .dismiss:
            onDismiss?()
        case .select(let editorId):
            onSelect?(editorId)
        case .toggleBookmark(let editorId):
            onToggleBookmark?(editorId)
        case .highlight(let editorId):
            onHighlight?(editorId)
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
            let editorId = EditorChooserKeyboardRouter.movedSelectionForTesting(
                delta: delta,
                items: items,
                selectedEditorId: selectedEditorId
            )
        else {
            return
        }

        onHighlight?(editorId)
    }

    private func activateCurrentSelection() {
        guard
            let editorId = EditorChooserKeyboardRouter.currentSelectionForTesting(
                items: items,
                selectedEditorId: selectedEditorId
            )
        else {
            return
        }

        onSelect?(editorId)
    }
}
