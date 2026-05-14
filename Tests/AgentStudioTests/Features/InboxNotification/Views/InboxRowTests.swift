import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxRow")
struct InboxRowTests {
    @Test("row reserves the shared sidebar leading column")
    func rowReservesSharedSidebarLeadingColumn() {
        #expect(InboxRow.leadingIndicatorColumnWidth == AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth)
    }

    @Test("row renders metadata with the shared sidebar line primitive")
    func rowRendersMetadataWithSharedSidebarLinePrimitive() {
        let sourceLine = InboxRow.metadataLine(text: "askluna · askluna")
        let placementLine = InboxRow.metadataLine(
            iconSystemName: InboxRow.placementMetadataIconSystemName,
            text: "Tab Terminal · Pane project-dev",
            prominence: .secondary
        )
        let detailLine = InboxRow.metadataLine(text: "Output appeared while you were away", prominence: .tertiary)

        #expect(String(describing: type(of: sourceLine)) == "SidebarMetadataLine")
        #expect(sourceLine.iconSystemName == nil)
        #expect(sourceLine.text == "askluna · askluna")
        #expect(sourceLine.prominence == .secondary)
        #expect(placementLine.iconSystemName == nil)
        #expect(placementLine.text == "Tab Terminal · Pane project-dev")
        #expect(placementLine.prominence == .secondary)
        #expect(detailLine.text == "Output appeared while you were away")
        #expect(detailLine.prominence == .tertiary)
    }

    @Test("placement metadata keeps reserved title column without terminal leading icon")
    func placementMetadataKeepsReservedTitleColumnWithoutTerminalLeadingIcon() {
        #expect(InboxRow.placementMetadataIconSystemName == nil)
        #expect(InboxRow.usesReservedMetadataIconColumn)
    }
}
