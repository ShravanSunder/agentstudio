import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("Tab bar chrome layout plan")
struct TabBarChromeLayoutPlanTests {
    @Test("workspace tab controls are just the tab strip when not overflowing")
    func workspaceTabControlsAreJustTabStripWhenNotOverflowing() {
        let plan = TabBarChromeLayoutPlan(isOverflowing: false)

        #expect(plan.workspaceTabControls == [.tabStrip])
        #expect(!plan.showsTrailingControls)
        #expect(plan.trailingControls.isEmpty)
    }

    @Test("overflow adds scroll chevrons as trailing controls after the tab strip")
    func overflowAddsScrollChevronsAsTrailingControlsAfterTabStrip() {
        let plan = TabBarChromeLayoutPlan(isOverflowing: true)

        #expect(plan.showsTrailingControls)
        #expect(plan.workspaceTabControls == [.tabStrip, .overflowLeft, .overflowRight])
        #expect(plan.trailingControls == [.overflowLeft, .overflowRight])
    }

    @Test("classifies toolbar control styles")
    func classifiesToolbarControlStyles() {
        let plan = TabBarChromeLayoutPlan(isOverflowing: true)

        #expect(plan.controlStyles[.overflowLeft] == .plainIcon)
        #expect(plan.controlStyles[.overflowRight] == .plainIcon)
        #expect(plan.controlStyles[.tabStrip] == .tabStrip)
    }

    @Test("targets clipped tabs using scroll area frame in tab bar coordinates")
    func targetsClippedTabsUsingScrollAreaFrameInTabBarCoordinates() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let thirdTabId = UUID()
        let orderedTabIds = [firstTabId, secondTabId, thirdTabId]
        let tabFrames = [
            firstTabId: CGRect(x: 92, y: 0, width: 100, height: 32),
            secondTabId: CGRect(x: 196, y: 0, width: 100, height: 32),
            thirdTabId: CGRect(x: 300, y: 0, width: 100, height: 32),
        ]
        let visibleFrame = CGRect(x: 100, y: 0, width: 200, height: 36)

        #expect(
            TabBarOverflowScrollTargetResolver.targetTabId(
                direction: .right,
                orderedTabIds: orderedTabIds,
                tabFrames: tabFrames,
                visibleFrame: visibleFrame
            ) == thirdTabId
        )
        #expect(
            TabBarOverflowScrollTargetResolver.targetTabId(
                direction: .left,
                orderedTabIds: orderedTabIds,
                tabFrames: tabFrames,
                visibleFrame: visibleFrame
            ) == firstTabId
        )
    }
}
