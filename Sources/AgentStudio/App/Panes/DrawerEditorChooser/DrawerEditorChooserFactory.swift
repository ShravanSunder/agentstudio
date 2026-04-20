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
        uiState: UIStateAtom,
        paneId: UUID,
        canOpenTarget: Bool,
        refreshInstalledTargets: @escaping @MainActor () -> [ExternalEditorTarget],
        onOpenFinder: @escaping () -> Void,
        onOpenEditor: @escaping (EditorTargetId) -> Void
    ) -> DrawerOverlay.TrailingActions {
        let items = uiState.availableEditorTargets
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
                    bookmarkedEditorId: uiState.editorChooserState.bookmarkedEditorId,
                    directLaunchHintText: directLaunchHintText,
                    directLaunchShortcutText: directLaunchShortcutText,
                    style: .standard,
                    onSelect: { editorId in
                        onOpenEditor(editorId)
                        uiState.setOpenEditorPane(nil)
                    },
                    onToggleBookmark: { editorId in
                        uiState.setBookmarkedEditor(
                            uiState.editorChooserState.bookmarkedEditorId == editorId ? nil : editorId
                        )
                    },
                    onDismiss: {
                        uiState.setOpenEditorPane(nil)
                    },
                    matchesAdditionalDismissShortcut: { event in
                        guard let trigger = ShortcutDecoder.decode(event: event) else { return false }
                        return trigger == AppShortcut.openPaneLocationInEditorMenu.trigger
                    }
                )
            ),
            editorMenuPresented: Binding(
                get: { uiState.editorChooserState.openForPaneId == paneId },
                set: { isPresented in
                    if isPresented {
                        uiState.setAvailableEditorTargets(refreshInstalledTargets())
                        uiState.setOpenEditorPane(paneId)
                    } else {
                        uiState.setOpenEditorPane(nil)
                    }
                }
            ),
            buttonTitle: buttonTitle(
                bookmarkedEditorId: uiState.editorChooserState.bookmarkedEditorId,
                targets: uiState.availableEditorTargets.isEmpty
                    ? ExternalEditorTarget.curatedOrder
                    : uiState.availableEditorTargets
            ),
            onOpenFinder: onOpenFinder
        )
    }
}
