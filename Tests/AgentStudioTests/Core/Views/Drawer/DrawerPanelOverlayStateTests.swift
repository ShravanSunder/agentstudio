import CoreGraphics
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct DrawerPanelOverlayStateTests {
    // MARK: - Frame preference reducer stability

    @Test
    func drawerPanelGlobalFrameKey_keepsRealFrameWhenZeroIsPublished() {
        var globalFrame = CGRect(x: 10, y: 20, width: 200, height: 100)
        DrawerPanelGlobalFrameKey.reduce(value: &globalFrame) { .zero }

        #expect(globalFrame == CGRect(x: 10, y: 20, width: 200, height: 100))
    }

    @Test
    func drawerPanelFrameInTabKey_keepsRealFrameWhenZeroIsPublished() {
        var tabFrame = CGRect(x: 30, y: 40, width: 220, height: 120)
        DrawerPanelFrameInTabKey.reduce(value: &tabFrame) { .zero }

        #expect(tabFrame == CGRect(x: 30, y: 40, width: 220, height: 120))
    }

    @Test
    func drawerIconBarFrameKey_keepsRealFrameWhenZeroIsPublished() {
        var iconBarFrame = CGRect(x: 5, y: 6, width: 80, height: 30)
        DrawerIconBarFrameKey.reduce(value: &iconBarFrame) { .zero }

        #expect(iconBarFrame == CGRect(x: 5, y: 6, width: 80, height: 30))
    }

    @Test
    func drawerPanelGlobalFrameKey_acceptsRealFrameWhenPublished() {
        var globalFrame: CGRect = .zero
        DrawerPanelGlobalFrameKey.reduce(value: &globalFrame) {
            CGRect(x: 100, y: 200, width: 500, height: 220)
        }

        #expect(globalFrame == CGRect(x: 100, y: 200, width: 500, height: 220))
    }

    @Test
    func drawerPanelGlobalFrameKey_acceptsLaterNonZeroUpdate() {
        var globalFrame = CGRect(x: 10, y: 20, width: 200, height: 100)
        DrawerPanelGlobalFrameKey.reduce(value: &globalFrame) {
            CGRect(x: 50, y: 60, width: 300, height: 150)
        }

        #expect(globalFrame == CGRect(x: 50, y: 60, width: 300, height: 150))
    }

    // MARK: - Dismiss monitor outside-click contract

    @Test
    func drawerDismissMonitor_outsideClickDismisses_evenWhenIconBarFrameIsZero() {
        let monitor = DrawerDismissMonitor()
        monitor.drawerRect = CGRect(x: 100, y: 100, width: 500, height: 220)
        monitor.iconBarRect = .zero

        #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 40, y: 40)))
        #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 200, y: 200)))
    }

    @Test
    func drawerDismissMonitor_excludesDrawerAndIconBarRegions() {
        let monitor = DrawerDismissMonitor()
        monitor.drawerRect = CGRect(x: 100, y: 100, width: 500, height: 220)
        monitor.iconBarRect = CGRect(x: 240, y: 330, width: 160, height: 28)

        #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 120, y: 120)))
        #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 260, y: 340)))
        #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 40, y: 40)))
    }

    @Test
    func drawerDismissMonitor_outsideClickStillDismisses_afterStaleFrameZeroReset() {
        // Models the failure mode the empty-rect early-exit caused: if the
        // dismiss monitor's `drawerRect` is reset to .zero (which used to
        // happen because the preference reducer accepted zero updates),
        // the monitor must still dismiss on outside clicks. Empty rect
        // contains nothing — so any click is outside.
        let monitor = DrawerDismissMonitor()
        monitor.drawerRect = CGRect(x: 100, y: 100, width: 500, height: 220)
        monitor.iconBarRect = .zero

        #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 40, y: 40)))

        monitor.drawerRect = .zero

        #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 40, y: 40)))
        #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 200, y: 200)))
    }

    @Test
    func drawerDismissMonitor_invokesDismissOnceForOutsidePoint() {
        let monitor = DrawerDismissMonitor()
        monitor.drawerRect = CGRect(x: 100, y: 100, width: 500, height: 220)
        monitor.iconBarRect = CGRect(x: 240, y: 330, width: 160, height: 28)
        var dismissCount = 0
        monitor.onDismiss = { dismissCount += 1 }

        #expect(!monitor.handleMouseDown(globalPoint: CGPoint(x: 120, y: 120)))
        #expect(!monitor.handleMouseDown(globalPoint: CGPoint(x: 260, y: 340)))
        #expect(monitor.handleMouseDown(globalPoint: CGPoint(x: 40, y: 40)))
        #expect(dismissCount == 1)
    }
}
