import SwiftUI

@MainActor
enum DrawerEditorChooserFactory {
    private static let maxButtonTitleLength = 20
    static let directLaunchHintText = "Launch bookmarked"
    static let directLaunchShortcutText =
        AppCommand.openPaneLocationInBookmarkedEditor.definition.keyBinding?.displayString ?? ""

    static func buttonTitle(
        bookmarkedEditorId: EditorTargetId?,
        targets: [ExternalEditorTarget]
    ) -> String? {
        guard
            let bookmarkedEditorId,
            let title = targets.first(where: { $0.id == bookmarkedEditorId })?.title
        else {
            return nil
        }

        guard title.count > maxButtonTitleLength else { return title }
        return String(title.prefix(maxButtonTitleLength - 1)) + "…"
    }

    static func makeTrailingActions(
        editorChooser: EditorChooserState,
        paneId: UUID,
        workspaceWindowId: UUID? = nil,
        canOpenTarget: Bool,
        refreshInstalledTargets: @escaping @MainActor () -> [ExternalEditorTarget],
        onOpenFinder: @escaping () -> Void,
        onOpenEditor: @escaping (EditorTargetId) -> Void
    ) -> DrawerOverlay.TrailingActions {
        let transientSurfaceKind = TransientKeyboardSurfaceKind.editorChooser(paneId: paneId)
        let items = editorChooser.availableTargets
            .enumerated()
            .map { index, target in
                EditorChoiceItem(
                    id: target.id,
                    title: target.title,
                    appIcon: target.appIcon,
                    shortcutNumber: index + 1
                )
            }
        return DrawerOverlay.TrailingActions(
            canOpenTarget: canOpenTarget,
            editorMenuContent: AnyView(
                DrawerEditorChooserPopoverHost(
                    items: items,
                    bookmarkedEditorId: editorChooser.bookmarkedEditorId,
                    directLaunchHintText: directLaunchHintText,
                    directLaunchShortcutText: directLaunchShortcutText,
                    style: .standard,
                    onSelect: { editorId in
                        onOpenEditor(editorId)
                        editorChooser.setOpenEditorPane(nil)
                    },
                    onToggleBookmark: { editorId in
                        editorChooser.setBookmarkedEditor(
                            editorChooser.bookmarkedEditorId == editorId ? nil : editorId
                        )
                    },
                    onDismiss: {
                        editorChooser.setOpenEditorPane(nil)
                    },
                    matchesAdditionalDismissShortcut: { event in
                        guard let trigger = ShortcutDecoder.decode(event: event) else { return false }
                        return TransientKeyboardSurfaceDismissRouter.shouldDismiss(
                            trigger: trigger,
                            policy: transientSurfaceKind.defaultPolicy
                        )
                    }
                )
                .transientKeyboardSurface(
                    transientSurfaceKind,
                    workspaceWindowId: workspaceWindowId
                )
            ),
            editorMenuPresented: Binding(
                get: { editorChooser.openForPaneId == paneId },
                set: { isPresented in
                    if isPresented {
                        editorChooser.setAvailableTargets(refreshInstalledTargets())
                        editorChooser.setOpenEditorPane(paneId)
                    } else {
                        editorChooser.setOpenEditorPane(nil)
                    }
                }
            ),
            buttonTitle: buttonTitle(
                bookmarkedEditorId: editorChooser.bookmarkedEditorId,
                targets: editorChooser.availableTargets.isEmpty
                    ? ExternalEditorTarget.curatedOrder
                    : editorChooser.availableTargets
            ),
            onOpenFinder: onOpenFinder
        )
    }
}

private struct DrawerEditorChooserPopoverHost: View {
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
    @State private var hoveredRowId: EditorTargetId?

    var body: some View {
        EditorChooserPopover(
            items: items,
            bookmarkedEditorId: bookmarkedEditorId,
            directLaunchHintText: directLaunchHintText,
            directLaunchShortcutText: directLaunchShortcutText,
            style: style,
            onSelect: onSelect,
            onToggleBookmark: onToggleBookmark,
            onDismiss: onDismiss,
            matchesAdditionalDismissShortcut: matchesAdditionalDismissShortcut,
            selectedEditorId: $selectedEditorId,
            hoveredRowId: $hoveredRowId
        )
    }
}
