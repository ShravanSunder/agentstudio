import CoreGraphics
import Testing

@testable import AgentStudio

@Suite
struct HoverTooltipPlacementTests {

    @Test
    func tooltipX_centersWhenEnoughSpaceIsAvailable() {
        let anchorFrame = CGRect(x: 60, y: 0, width: 24, height: 24)
        let tooltipSize = CGSize(width: 100, height: 32)

        let x = HoverTooltipPlacement.clampedLeadingX(
            anchorFrame: anchorFrame,
            tooltipSize: tooltipSize,
            availableWidth: 220
        )

        #expect(x == 22)
    }

    @Test
    func tooltipX_clampsToLeadingInsetNearLeftEdge() {
        let anchorFrame = CGRect(x: 0, y: 0, width: 24, height: 24)
        let tooltipSize = CGSize(width: 120, height: 32)

        let x = HoverTooltipPlacement.clampedLeadingX(
            anchorFrame: anchorFrame,
            tooltipSize: tooltipSize,
            availableWidth: 220
        )

        #expect(x == HoverTooltipPlacement.defaultEdgeInset)
    }

    @Test
    func tooltipX_clampsToTrailingInsetNearRightEdge() {
        let anchorFrame = CGRect(x: 188, y: 0, width: 24, height: 24)
        let tooltipSize = CGSize(width: 120, height: 32)

        let x = HoverTooltipPlacement.clampedLeadingX(
            anchorFrame: anchorFrame,
            tooltipSize: tooltipSize,
            availableWidth: 220
        )

        #expect(x == 94)
    }

    @Test
    func tooltipY_usesContainerOffsetForSingleLineToolbars() {
        let anchorFrame = CGRect(x: 20, y: 10, width: 24, height: 24)

        let y = HoverTooltipPlacement.positionedY(
            anchorFrame: anchorFrame,
            verticalAnchor: .containerTop,
            verticalOffset: HoverTooltipPlacement.defaultVerticalOffset
        )

        #expect(y == HoverTooltipPlacement.defaultVerticalOffset)
    }

    @Test
    func tooltipY_canAnchorBelowHoveredControlForMultiRowToolbars() {
        let anchorFrame = CGRect(x: 20, y: 18, width: 24, height: 24)

        let y = HoverTooltipPlacement.positionedY(
            anchorFrame: anchorFrame,
            verticalAnchor: .belowAnchor,
            verticalOffset: HoverTooltipPlacement.belowAnchorVerticalOffset
        )

        #expect(y == 48)
    }
}
