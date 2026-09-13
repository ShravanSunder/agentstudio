import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer keyboard row chrome", .serialized)
struct RepoExplorerKeyboardChromeTests {
    @Test("keyboard paint retains row bindings and native layout while updating selected rows")
    func keyboardPaintPreservesContentAndLayout() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let tabID = UUIDv7.generate()
        let paneIDs = [UUIDv7.generate(), UUIDv7.generate()]
        let snapshot = navigationSnapshot(paneIDs.map { .unassociatedPane(paneID: $0, tabID: tabID) })
        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        let table = try #require(firstRepoExplorerKeyboardDescendant(NSTableView.self, in: fixture.host))
        let firstCell = try #require(
            table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )
        let secondCell = try #require(
            table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )
        let firstBinding = firstCell.currentBindingIdentity
        let secondBinding = secondCell.currentBindingIdentity
        let nativeApplyCount = fixture.materializer.nativeTransactionApplyCount
        let layoutPassCount = fixture.materializer.forcedLayoutPassCount
        let frameUpdateCount = fixture.materializer.tableFrameUpdateCount

        fixture.materializer.setShowsKeyboardHints(true)
        #expect(firstCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "1")
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "2")
        try fixture.send(.moveSelectionDown)

        #expect(!firstCell.hostingView.rootView.slot.keyboardPresentation.isSelected)
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.isSelected)
        #expect(table.selectedRow == 1)
        #expect(fixture.window.firstResponder === fixture.host)
        #expect(firstCell.currentBindingIdentity == firstBinding)
        #expect(secondCell.currentBindingIdentity == secondBinding)
        #expect(fixture.materializer.nativeTransactionApplyCount == nativeApplyCount)
        #expect(fixture.materializer.forcedLayoutPassCount == layoutPassCount)
        #expect(fixture.materializer.tableFrameUpdateCount == frameUpdateCount)
        #expect(fixture.recorder.focusedPaneIDs.isEmpty)
        #expect(fixture.recorder.commandRequests.isEmpty)

        fixture.materializer.setShowsKeyboardHints(false)
        #expect(firstCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay == nil)
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay == nil)
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.isSelected)
        #expect(table.selectionHighlightStyle == .none)
    }
}
