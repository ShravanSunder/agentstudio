import Testing

@testable import AgentStudio

@Suite(.serialized)
struct CollapsedBarTextAllocatorTests {
    @Test
    func fittingSegments_keepTheirIntrinsicWidths() {
        let parts = [
            CollapsedBarLabelPart(icon: .octicon("octicon-repo"), text: "vm", weight: .semibold),
            CollapsedBarLabelPart(icon: .octicon("octicon-git-worktree"), text: "main", weight: .regular),
            CollapsedBarLabelPart(icon: .octicon("octicon-git-branch"), text: "feature", weight: .regular),
        ]

        let widths = CollapsedBarTextAllocator.allocatedTextWidths(for: parts, availableLabelWidth: 400)

        #expect(widths.count == 3)
        #expect(widths[0] > 0)
        #expect(widths[1] > 0)
        #expect(widths[2] > 0)
        #expect(widths[0] < widths[2])
    }

    @Test
    func shortSegmentKeepsSpace_whileLongerSegmentsShareRemainder() {
        let parts = [
            CollapsedBarLabelPart(icon: .octicon("octicon-repo"), text: "vm", weight: .semibold),
            CollapsedBarLabelPart(icon: .octicon("octicon-git-worktree"), text: "wt", weight: .regular),
            CollapsedBarLabelPart(
                icon: .octicon("octicon-git-branch"),
                text: "luna-356-management-mode-shortcut-ux-fixes",
                weight: .regular
            ),
        ]

        let widths = CollapsedBarTextAllocator.allocatedTextWidths(for: parts, availableLabelWidth: 160)

        #expect(widths.count == 3)
        #expect(widths[0] < widths[2])
        #expect(widths[1] < widths[2])
        #expect(widths[0] > 0)
        #expect(widths[1] > 0)
        #expect(widths[2] > 0)
    }

    @Test
    func equalOverflowingSegments_receiveEqualSharedBudget() {
        let parts = [
            CollapsedBarLabelPart(icon: .octicon("octicon-repo"), text: "alpha-alpha-alpha", weight: .semibold),
            CollapsedBarLabelPart(icon: .octicon("octicon-git-worktree"), text: "beta-beta-beta", weight: .regular),
        ]

        let widths = CollapsedBarTextAllocator.allocatedTextWidths(for: parts, availableLabelWidth: 90)

        #expect(widths.count == 2)
        #expect(abs(widths[0] - widths[1]) < 1)
    }
}
