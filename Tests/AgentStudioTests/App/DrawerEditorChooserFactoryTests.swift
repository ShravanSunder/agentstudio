import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct DrawerEditorChooserFactoryTests {
    @Test
    func buttonTitle_withoutBookmark_isNil() {
        let targets = [
            ExternalEditorTarget.cursor,
            ExternalEditorTarget.vscode,
        ]

        let title = DrawerEditorChooserFactory.buttonTitle(
            bookmarkedEditorId: nil,
            targets: targets
        )

        #expect(title == nil)
    }

    @Test
    func buttonTitle_withBookmark_usesBookmarkedTitle() {
        let targets = [
            ExternalEditorTarget.cursor,
            ExternalEditorTarget.vscode,
        ]

        let title = DrawerEditorChooserFactory.buttonTitle(
            bookmarkedEditorId: "vscode",
            targets: targets
        )

        #expect(title == "VS Code")
    }

    @Test
    func buttonTitle_truncatesAfterTwentyCharacters() {
        let targets = [
            ExternalEditorTarget(
                id: "long",
                title: "Antigravity Something",
                bundleIdentifier: "com.example.long",
                cliFallbacks: [],
                appIcon: nil
            )
        ]

        let title = DrawerEditorChooserFactory.buttonTitle(
            bookmarkedEditorId: "long",
            targets: targets
        )

        #expect(title == "Antigravity Somethi…")
    }

    @Test
    func makeTrailingActions_refreshesInstalledTargetsOnlyWhenOpeningChooser() {
        let uiState = UIStateAtom()
        let paneId = UUID()
        var refreshCallCount = 0

        let actions = DrawerEditorChooserFactory.makeTrailingActions(
            uiState: uiState,
            paneId: paneId,
            canOpenTarget: true,
            refreshInstalledTargets: {
                refreshCallCount += 1
                return [.cursor]
            },
            onOpenFinder: {},
            onOpenEditor: { _ in }
        )

        #expect(refreshCallCount == 0)
        #expect(uiState.availableEditorTargets.isEmpty)

        actions.editorMenuPresented.wrappedValue = true

        #expect(refreshCallCount == 1)
        #expect(uiState.availableEditorTargets.map(\.id) == [ExternalEditorTarget.cursor.id])
        #expect(uiState.editorChooserState.openForPaneId == paneId)
    }

    @Test
    func makeTrailingActions_closingChooserClearsOpenStateWithoutRefreshing() {
        let uiState = UIStateAtom()
        let paneId = UUID()
        var refreshCallCount = 0

        let actions = DrawerEditorChooserFactory.makeTrailingActions(
            uiState: uiState,
            paneId: paneId,
            canOpenTarget: true,
            refreshInstalledTargets: {
                refreshCallCount += 1
                return [.cursor]
            },
            onOpenFinder: {},
            onOpenEditor: { _ in }
        )

        actions.editorMenuPresented.wrappedValue = true
        actions.editorMenuPresented.wrappedValue = false

        #expect(refreshCallCount == 1)
        #expect(uiState.editorChooserState.openForPaneId == nil)
    }
}
