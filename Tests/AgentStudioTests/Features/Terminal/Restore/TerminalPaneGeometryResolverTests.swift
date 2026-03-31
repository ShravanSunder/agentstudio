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
            dividerThickness: divider
        )

        let gap = AppStyle.paneGap
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
            dividerThickness: 1
        )

        #expect(resolved[pane] != CGRect(x: 0, y: 0, width: 800, height: 600))
    }
}
