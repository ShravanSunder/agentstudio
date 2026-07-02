import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite("Tab bar chrome layout plan")
struct TabBarChromeLayoutPlanTests {
    @Test("places plus after tab strip divider")
    func placesPlusAfterTabStripDivider() {
        let plan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: false)

        #expect(
            plan.controlOrder == [
                .sidebarSurfaces,
                .divider,
                .watchFolder,
                .managementLayer,
                .arrangement,
                .tabStrip,
                .divider,
                .newTab,
            ])
        #expect(
            plan.leadingControls == [
                .sidebarSurfaces,
                .divider,
                .watchFolder,
                .managementLayer,
                .arrangement,
            ])
        #expect(plan.trailingControls == [.divider, .newTab])
    }

    @Test("omits plus when the add action is unavailable")
    func omitsPlusWhenAddActionUnavailable() {
        let plan = TabBarChromeLayoutPlan(hasNewTab: false, isOverflowing: false)

        #expect(!plan.controlOrder.contains(.newTab))
        #expect(Array(plan.controlOrder.suffix(2)) == [.arrangement, .tabStrip])
    }

    @Test("places overflow before divider and plus")
    func placesOverflowBeforeDividerAndPlus() {
        let normalPlan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: false)
        let overflowPlan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: true)

        #expect(normalPlan.showsTrailingControls)
        #expect(Array(normalPlan.controlOrder.suffix(3)) == [.tabStrip, .divider, .newTab])
        #expect(overflowPlan.showsTrailingControls)
        #expect(
            Array(overflowPlan.controlOrder.suffix(5)) == [
                .overflowLeft, .overflowRight, .overflowMenu, .divider, .newTab,
            ])
        #expect(overflowPlan.trailingControls == [.overflowLeft, .overflowRight, .overflowMenu, .divider, .newTab])
    }

    @Test("uses exact overflowing toolbar order without GitHub top chrome")
    func usesExactOverflowingToolbarOrderWithoutGitHubTopChrome() {
        let plan = TabBarChromeLayoutPlan(hasNewTab: true, isOverflowing: true)

        #expect(
            plan.controlOrder == [
                .sidebarSurfaces,
                .divider,
                .watchFolder,
                .managementLayer,
                .arrangement,
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

        #expect(plan.controlStyles[.sidebarSurfaces] == .plainIcon)
        #expect(plan.controlStyles[.watchFolder] == .toolbarButton)
        #expect(plan.controlStyles[.managementLayer] == .toolbarButton)
        #expect(plan.controlStyles[.arrangement] == .toolbarButton)
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
