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
    @Binding var selectedEditorId: EditorTargetId?
    @Binding var hoveredRowId: EditorTargetId?

    var body: some View {
        EditorChooserMenuContent(
            items: items,
            bookmarkedEditorId: bookmarkedEditorId,
            selectedEditorId: selectedEditorId,
            directLaunchHintText: directLaunchHintText,
            directLaunchShortcutText: directLaunchShortcutText,
            style: style,
            onSelect: onSelect,
            onToggleBookmark: onToggleBookmark,
            hoveredRowId: $hoveredRowId
        )
        .background(
            SelectablePopoverKeyboardBridge(
                items: keyboardItems,
                selectedItemId: selectedEditorId,
                auxiliaryAction: SelectablePopoverAuxiliaryAction(key: "b") { editorId in
                    selectedEditorId = editorId
                    onToggleBookmark(editorId)
                },
                onSelect: { editorId in
                    selectedEditorId = editorId
                    onSelect(editorId)
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

    private var keyboardItems: [SelectablePopoverKeyboardItem<EditorTargetId>] {
        items.map {
            SelectablePopoverKeyboardItem(
                id: $0.id,
                shortcutNumber: $0.shortcutNumber,
                supportsAuxiliaryAction: true
            )
        }
    }

    private func repairSelection() {
        if let selectedEditorId, itemIDs.contains(selectedEditorId) {
            return
        }
        selectedEditorId = SelectablePopoverKeyboardRouter.defaultSelection(
            items: keyboardItems,
            preferredItemId: bookmarkedEditorId
        )
    }
}
