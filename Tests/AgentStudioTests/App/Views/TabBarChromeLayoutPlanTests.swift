import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("Tab bar chrome layout plan")
struct TabBarChromeLayoutPlanTests {
    @Test("places plus after tab strip divider")
    func placesPlusAfterTabStripDivider() {
        let plan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: false)

        #expect(plan.workspaceTabControls == [.tabStrip, .divider, .newTab])
        #expect(plan.trailingControls == [.divider, .newTab])
    }

    @Test("omits plus when the add action is unavailable")
    func omitsPlusWhenAddActionUnavailable() {
        let plan = TabBarChromeLayoutPlan(hasNewTab: false, isOverflowing: false)

        #expect(plan.workspaceTabControls == [.tabStrip])
        #expect(plan.trailingControls.isEmpty)
    }

    @Test("places overflow before divider and plus")
    func placesOverflowBeforeDividerAndPlus() {
        let normalPlan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: false)
        let overflowPlan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: true)

        #expect(normalPlan.showsTrailingControls)
        #expect(normalPlan.workspaceTabControls == [.tabStrip, .divider, .newTab])
        #expect(overflowPlan.showsTrailingControls)
        #expect(
            overflowPlan.workspaceTabControls == [
                .tabStrip, .overflowLeft, .overflowRight, .overflowMenu, .divider, .newTab,
            ])
        #expect(overflowPlan.trailingControls == [.overflowLeft, .overflowRight, .overflowMenu, .divider, .newTab])
    }

    @Test("workspace tab layout excludes fixed native toolbar controls")
    func workspaceTabLayoutExcludesFixedNativeToolbarControls() {
        let plan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: true)

        #expect(
            plan.workspaceTabControls == [
                .tabStrip,
                .overflowLeft,
                .overflowRight,
                .overflowMenu,
                .divider,
                .newTab,
            ])
    }

    @Test("classifies toolbar control styles")
    func classifiesToolbarControlStyles() {
        let plan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: true)

        #expect(plan.controlStyles[.newTab] == .toolbarButton)
        #expect(plan.controlStyles[.overflowLeft] == .plainIcon)
        #expect(plan.controlStyles[.overflowRight] == .plainIcon)
        #expect(plan.controlStyles[.overflowMenu] == .plainIcon)
        #expect(plan.controlStyles[.divider] == .divider)
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
