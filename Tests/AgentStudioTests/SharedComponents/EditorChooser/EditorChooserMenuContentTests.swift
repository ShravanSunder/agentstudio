import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct EditorChooserMenuContentTests {
    @Test
    func displayItems_keepsBookmarkMarkedButPreservesCatalogOrder() {
        let items = [
            EditorChoiceItem(id: "cursor", title: "Cursor", appIcon: nil, shortcutNumber: 1),
            EditorChoiceItem(id: "vscode", title: "VS Code", appIcon: nil, shortcutNumber: 2),
        ]
        let rows = EditorChooserMenuContent.makeDisplayItems(
            items: items,
            bookmarkedEditorId: "vscode"
        )

        #expect(rows.map(\.id) == ["cursor", "vscode"])
        #expect(rows.map(\.shortcutNumber) == [1, 2])
        #expect(rows.last?.isBookmarked == true)
    }
}
