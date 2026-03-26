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
            root: .split(
                Layout.Split(
                    direction: .horizontal,
                    ratio: 0.5,
                    left: .leaf(paneId: paneA),
                    right: .leaf(paneId: paneB)
                )
            )
        )

        let resolved = TerminalPaneGeometryResolver.resolveFrames(
            for: layout,
            in: CGRect(x: 0, y: 0, width: 1000, height: 600),
            dividerThickness: 1
        )

        let gap = AppStyle.paneGap
        let paneWidth = (1000.0 - 1) / 2 - gap * 2
        let paneHeight = 600.0 - gap * 2
        #expect(resolved[paneA] == CGRect(x: gap, y: gap, width: paneWidth, height: paneHeight))
        #expect(
            resolved[paneB] == CGRect(x: gap + paneWidth + gap + 1 + gap, y: gap, width: paneWidth, height: paneHeight))
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
