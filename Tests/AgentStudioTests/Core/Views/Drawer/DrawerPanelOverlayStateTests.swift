import CoreGraphics
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct DrawerPanelOverlayStateTests {
    @Test
    func drawerFramePreferenceKeysAllowZeroToResetStaleFrames() {
        var globalFrame = CGRect(x: 10, y: 20, width: 200, height: 100)
        DrawerPanelGlobalFrameKey.reduce(value: &globalFrame) { .zero }

        var tabFrame = CGRect(x: 30, y: 40, width: 220, height: 120)
        DrawerPanelFrameInTabKey.reduce(value: &tabFrame) { .zero }

        #expect(globalFrame == .zero)
        #expect(tabFrame == .zero)
    }

    @Test
    func drawerDismissMonitorDoesNotDismissUntilDrawerFrameIsKnown() {
        let monitor = DrawerDismissMonitor()
        monitor.drawerRect = .zero
        monitor.iconBarRect = .zero

        #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 20, y: 20)))

        monitor.drawerRect = CGRect(x: 10, y: 10, width: 100, height: 80)
        #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 30, y: 30)))
        #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 200, y: 200)))
    }
}
