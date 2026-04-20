import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct DrawerEditorChooserFactoryTests {
    @Test
    func buttonTitle_withoutBookmark_isNil() {
        let items = [
            EditorChoiceItem(id: "cursor", title: "Cursor", appIcon: nil, shortcutNumber: 1),
            EditorChoiceItem(id: "vscode", title: "VS Code", appIcon: nil, shortcutNumber: 2),
        ]

        let title = DrawerEditorChooserFactory.buttonTitle(
            bookmarkedEditorId: nil,
            items: items
        )

        #expect(title == nil)
    }

    @Test
    func buttonTitle_withBookmark_usesBookmarkedTitle() {
        let items = [
            EditorChoiceItem(id: "cursor", title: "Cursor", appIcon: nil, shortcutNumber: 1),
            EditorChoiceItem(id: "vscode", title: "VS Code", appIcon: nil, shortcutNumber: 2),
        ]

        let title = DrawerEditorChooserFactory.buttonTitle(
            bookmarkedEditorId: "vscode",
            items: items
        )

        #expect(title == "VS Code")
    }

    @Test
    func buttonTitle_truncatesAfterTwentyCharacters() {
        let items = [
            EditorChoiceItem(
                id: "long",
                title: "Antigravity Something",
                appIcon: nil,
                shortcutNumber: 1
            )
        ]

        let title = DrawerEditorChooserFactory.buttonTitle(
            bookmarkedEditorId: "long",
            items: items
        )

        #expect(title == "Antigravity Somethi…")
    }
}
