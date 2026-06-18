import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxRow")
struct InboxRowTests {
    @Test("row renders metadata with the shared sidebar line primitive")
    func rowRendersMetadataWithSharedSidebarLinePrimitive() {
        let sourceLine = InboxRow.metadataLine(text: "askluna · askluna")
        let placementLine = InboxRow.metadataLine(
            iconSystemName: InboxRow.placementMetadataIconSystemName,
            text: "Tab Terminal · Pane project-dev",
            prominence: .secondary
        )
        let detailLine = InboxRow.metadataLine(text: "3 files changed", prominence: .tertiary)

        #expect(String(describing: type(of: sourceLine)) == "SidebarMetadataLine")
        #expect(sourceLine.iconSystemName == nil)
        #expect(sourceLine.text == "askluna · askluna")
        #expect(sourceLine.prominence == .secondary)
        #expect(placementLine.iconSystemName == nil)
        #expect(placementLine.text == "Tab Terminal · Pane project-dev")
        #expect(placementLine.prominence == .secondary)
        #expect(detailLine.text == "3 files changed")
        #expect(detailLine.prominence == .tertiary)
    }

    @Test("placement metadata removes the unread indicator column")
    func placementMetadataRemovesUnreadIndicatorColumn() {
        #expect(InboxRow.placementMetadataIconSystemName == nil)
        #expect(InboxRow.metadataLine(text: "askluna").reservesIconColumn == false)
    }

    @Test("row state and content mode controls use distinct icons")
    func rowStateAndContentModeControlsUseDistinctIcons() {
        #expect(InboxSidebarHeader.rowStateIconName == "envelope.badge")
        #expect(InboxSidebarHeader.contentModeIconName == "dot.circle.viewfinder")
    }
}
