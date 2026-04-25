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
        editorChooser: EditorChooserAtom,
        paneId: UUID,
        canOpenTarget: Bool,
        refreshInstalledTargets: @escaping @MainActor () -> [ExternalEditorTarget],
        onOpenFinder: @escaping () -> Void,
        onOpenEditor: @escaping (EditorTargetId) -> Void
    ) -> DrawerOverlay.TrailingActions {
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
                EditorChooserPopover(
                    items: items,
                    bookmarkedEditorId: editorChooser.state.bookmarkedEditorId,
                    directLaunchHintText: directLaunchHintText,
                    directLaunchShortcutText: directLaunchShortcutText,
                    style: .standard,
                    onSelect: { editorId in
                        onOpenEditor(editorId)
                        editorChooser.setOpenEditorPane(nil)
                    },
                    onToggleBookmark: { editorId in
                        editorChooser.setBookmarkedEditor(
                            editorChooser.state.bookmarkedEditorId == editorId ? nil : editorId
                        )
                    },
                    onDismiss: {
                        editorChooser.setOpenEditorPane(nil)
                    },
                    matchesAdditionalDismissShortcut: { event in
                        guard let trigger = ShortcutDecoder.decode(event: event) else { return false }
                        return trigger == AppShortcut.openPaneLocationInEditorMenu.trigger
                    }
                )
            ),
            editorMenuPresented: Binding(
                get: { editorChooser.state.openForPaneId == paneId },
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
                bookmarkedEditorId: editorChooser.state.bookmarkedEditorId,
                targets: editorChooser.availableTargets.isEmpty
                    ? ExternalEditorTarget.curatedOrder
                    : editorChooser.availableTargets
            ),
            onOpenFinder: onOpenFinder
        )
    }
}
