import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TerminalPaneGeometryResolverTests {
    @Test
    func geometryResolver_derivesExactPaneFrames_fromWindowAndLayout() {
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(
            panes: [
                .init(paneId: paneA, ratio: 0.5),
                .init(paneId: paneB, ratio: 0.5),
            ],
            dividerIds: [UUID()]
        )

        let containerWidth: CGFloat = 1000
        let containerHeight: CGFloat = 600
        let divider: CGFloat = 1
        let resolved = TerminalPaneGeometryResolver.resolveFrames(
            for: layout,
            in: CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight),
            dividerThickness: divider,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        let gap = AppStyles.General.Layout.paneGap
        let rawSplitWidth = (containerWidth - divider) / 2
        let paneWidth = rawSplitWidth - gap * 2
        let paneHeight = containerHeight - gap * 2
        #expect(resolved[paneA] == CGRect(x: gap, y: gap, width: paneWidth, height: paneHeight))
        let paneBx = rawSplitWidth + divider + gap
        #expect(resolved[paneB] == CGRect(x: paneBx, y: gap, width: paneWidth, height: paneHeight))
    }

    @Test
    func geometryResolver_neverReturnsPlaceholder800x600() {
        let pane = UUID()
        let layout = Layout(paneId: pane)

        let resolved = TerminalPaneGeometryResolver.resolveFrames(
            for: layout,
            in: CGRect(x: 0, y: 0, width: 1200, height: 700),
            dividerThickness: 1,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        #expect(resolved[pane] != CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    /// Issue #11 — in a 2-row drawer layout, the "top" row must paint
    /// at the SMALLER y (visually higher) and the "bottom" row at the
    /// LARGER y (visually lower) under SwiftUI's flipped coordinate
    /// system (origin top-left, y grows down).
    ///
    /// The original geometry resolver had the labels inverted: the
    /// rect named `bottomRect` was placed at `availableRect.minY`
    /// (visually the top) and `topRect` was anchored below it. Top-row
    /// panes therefore rendered at the bottom of the panel and vice
    /// versa.
    @Test
    func geometryResolver_twoRowDrawer_topRowPaintsAtSmallerY_bottomRowAtLargerY() {
        let topPane = UUID()
        let bottomPane = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout(paneId: topPane),
            bottomRow: Layout(paneId: bottomPane),
            rowSplitRatio: 0.5
        )

        let resolved = TerminalPaneGeometryResolver.resolveFrames(
            for: layout,
            in: CGRect(x: 0, y: 0, width: 400, height: 200),
            dividerThickness: 1,
            collapsedPaneWidth: AppStyles.Shell.PaneChrome.collapsedBarWidth
        )

        let topFrame = resolved[topPane]!
        let bottomFrame = resolved[bottomPane]!

        // Top pane is visually higher → smaller minY (origin top-left).
        #expect(topFrame.minY < bottomFrame.minY)
        // Top pane occupies the upper half (around minY=0).
        #expect(topFrame.minY < 100)
        // Bottom pane occupies the lower half (around minY=100+).
        #expect(bottomFrame.minY > 100)
    }

    @Test
    func geometryResolver_usesProvidedCollapsedPaneWidth_forMinimizedPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(
            panes: [
                .init(paneId: paneA, ratio: 0.5),
                .init(paneId: paneB, ratio: 0.5),
            ],
            dividerIds: [UUID()]
        )

        let resolved = TerminalPaneGeometryResolver.resolveFrames(
            for: layout,
            in: CGRect(x: 0, y: 0, width: 1000, height: 600),
            dividerThickness: 1,
            minimizedPaneIds: [paneB],
            collapsedPaneWidth: 0
        )

        #expect((resolved[paneA]?.width ?? 0) > 980)
        #expect((resolved[paneB]?.minX ?? 0) >= 999)
    }
}
