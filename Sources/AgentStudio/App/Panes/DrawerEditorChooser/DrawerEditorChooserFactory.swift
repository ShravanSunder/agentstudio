import SwiftUI

@MainActor
enum DrawerEditorChooserFactory {
    private static let maxButtonTitleLength = 20

    static func buttonTitle(
        bookmarkedEditorId: EditorTargetId?,
        items: [EditorChoiceItem]
    ) -> String? {
        guard
            let bookmarkedEditorId,
            let title = items.first(where: { $0.id == bookmarkedEditorId })?.title
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
        onOpenFinder: @escaping () -> Void,
        onOpenEditor: @escaping (EditorTargetId) -> Void
    ) -> DrawerOverlay.TrailingActions {
        let items = ExternalEditorTarget.refreshInstalledTargets()
            .enumerated()
            .map { index, target in
                EditorChoiceItem(
                    id: target.id,
                    title: target.title,
                    appIcon: target.iconImage,
                    shortcutNumber: index + 1
                )
            }

        return DrawerOverlay.TrailingActions(
            canOpenTarget: canOpenTarget,
            editorMenuContent: AnyView(
                EditorChooserMenuContent(
                    items: items,
                    bookmarkedEditorId: uiState.editorChooserState.bookmarkedEditorId,
                    style: .standard,
                    onSelect: { editorId in
                        onOpenEditor(editorId)
                        uiState.setOpenEditorPane(nil)
                    },
                    onToggleBookmark: { editorId in
                        uiState.setBookmarkedEditor(
                            uiState.editorChooserState.bookmarkedEditorId == editorId ? nil : editorId
                        )
                    }
                )
            ),
            editorMenuPresented: Binding(
                get: { uiState.editorChooserState.openForPaneId == paneId },
                set: { isPresented in
                    uiState.setOpenEditorPane(isPresented ? paneId : nil)
                }
            ),
            buttonTitle: buttonTitle(
                bookmarkedEditorId: uiState.editorChooserState.bookmarkedEditorId,
                items: items
            ),
            onOpenFinder: onOpenFinder
        )
    }
}
