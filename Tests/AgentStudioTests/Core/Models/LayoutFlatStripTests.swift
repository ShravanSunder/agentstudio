import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class LayoutFlatStripTests {

    @Test
    func init_singlePane_createsSingleEntryWithFullRatio() {
        let paneId = UUID()

        let layout = Layout(paneId: paneId)

        #expect(layout.paneIds == [paneId])
        #expect(layout.ratios == [1.0])
        #expect(layout.dividerIds.isEmpty)
        #expect(!(layout.isSplit))
    }

    @Test
    func inserting_afterTarget_splitsTargetRatioAndInsertsAdjacentPane() {
        let paneA = UUID()
        let paneB = UUID()

        let layout = Layout(paneId: paneA)

        let updated = layout.inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        #expect(updated.paneIds == [paneA, paneB])
        #expect(updated.ratios.count == 2)
        #expect(updated.dividerIds.count == 1)
        #expect(updated.ratios[0] == 0.5)
        #expect(updated.ratios[1] == 0.5)
    }

    @Test
    func inserting_beforeTarget_splitsTargetRatioAndInsertsAdjacentPane() {
        let paneA = UUID()
        let paneB = UUID()

        let layout = Layout(paneId: paneA)

        let updated = layout.inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .before)

        #expect(updated.paneIds == [paneB, paneA])
        #expect(updated.ratios == [0.5, 0.5])
        #expect(updated.dividerIds.count == 1)
    }

    @Test
    func inserting_intoExistingStrip_onlySplitsTargetRatio() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()

        let layout = Layout(
            panes: [.init(paneId: paneA, ratio: 0.6), .init(paneId: paneB, ratio: 0.4)],
            dividerIds: [UUID()]
        )

        let updated = layout.inserting(paneId: paneC, at: paneB, direction: .horizontal, position: .after)

        #expect(updated.paneIds == [paneA, paneB, paneC])
        #expect(updated.dividerIds.count == 2)
        #expect(updated.ratios.count == 3)
        #expect(updated.ratios[0] == 0.6)
        #expect(updated.ratios[1] == 0.2)
        #expect(updated.ratios[2] == 0.2)
    }

    @Test
    func removing_middlePane_reassignsRatioToRightNeighbor() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()

        let layout = Layout(
            panes: [
                .init(paneId: paneA, ratio: 0.4),
                .init(paneId: paneB, ratio: 0.2),
                .init(paneId: paneC, ratio: 0.4),
            ],
            dividerIds: [UUID(), UUID()]
        )

        let updated = layout.removing(paneId: paneB)

        #expect(updated != nil)
        #expect(updated?.paneIds == [paneA, paneC])
        #expect(updated?.dividerIds.count == 1)
        #expect(updated?.ratios == [0.4, 0.6])
    }

    @Test
    func removing_lastPane_reassignsRatioToLeftNeighbor() {
        let paneA = UUID()
        let paneB = UUID()

        let layout = Layout(
            panes: [.init(paneId: paneA, ratio: 0.25), .init(paneId: paneB, ratio: 0.75)],
            dividerIds: [UUID()]
        )

        let updated = layout.removing(paneId: paneB)

        #expect(updated != nil)
        #expect(updated?.paneIds == [paneA])
        #expect(updated?.ratios == [1.0])
        #expect(updated?.dividerIds.isEmpty == true)
    }

    @Test
    func removing_onlyPane_returnsNil() {
        let layout = Layout(paneId: UUID())

        let updated = layout.removing(paneId: layout.paneIds[0])

        #expect(updated == nil)
    }

    @Test
    func ratioForDivider_returnsLocalAdjacentRatio() {
        let divider = UUID()
        let layout = Layout(
            panes: [
                .init(paneId: UUID(), ratio: 0.2),
                .init(paneId: UUID(), ratio: 0.3),
                .init(paneId: UUID(), ratio: 0.5),
            ],
            dividerIds: [divider, UUID()]
        )

        let ratio = layout.ratioForSplit(divider)

        #expect(ratio == 0.4)
    }

    @Test
    func resizingDivider_updatesOnlyAdjacentPaneRatios() {
        let dividerA = UUID()
        let dividerB = UUID()
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()

        let layout = Layout(
            panes: [
                .init(paneId: paneA, ratio: 0.2),
                .init(paneId: paneB, ratio: 0.3),
                .init(paneId: paneC, ratio: 0.5),
            ],
            dividerIds: [dividerA, dividerB]
        )

        let updated = layout.resizing(splitId: dividerA, ratio: 0.25)

        #expect(updated.paneIds == [paneA, paneB, paneC])
        #expect(updated.ratios.count == 3)
        #expect(updated.ratios[0] == 0.125)
        #expect(updated.ratios[1] == 0.375)
        #expect(updated.ratios[2] == 0.5)
    }

    @Test
    func equalized_setsAllPaneRatiosEqual() {
        let layout = Layout(
            panes: [
                .init(paneId: UUID(), ratio: 0.1),
                .init(paneId: UUID(), ratio: 0.2),
                .init(paneId: UUID(), ratio: 0.7),
            ],
            dividerIds: [UUID(), UUID()]
        )

        let updated = layout.equalized()

        #expect(updated.ratios == [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
    }

    @Test
    func nextAndPreviousFollowPaneOrder() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(
            panes: [
                .init(paneId: paneA, ratio: 0.2),
                .init(paneId: paneB, ratio: 0.3),
                .init(paneId: paneC, ratio: 0.5),
            ],
            dividerIds: [UUID(), UUID()]
        )

        #expect(layout.next(after: paneA) == paneB)
        #expect(layout.next(after: paneC) == paneA)
        #expect(layout.previous(before: paneA) == paneC)
        #expect(layout.previous(before: paneC) == paneB)
    }
}
