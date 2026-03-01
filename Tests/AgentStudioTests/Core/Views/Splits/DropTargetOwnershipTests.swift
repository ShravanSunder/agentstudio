import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropTargetOwnershipTests {
    @Test("tab-level split capture disabled while drawer modal is active")
    func tabLevelSplitCaptureDisabledForDrawerModal() {
        let expandedDrawerParentPaneId = UUIDv7.generate()

        let enabled = TerminalSplitContainer.shouldEnableTabLevelSplitDropCapture(
            isManagementModeActive: true,
            expandedDrawerParentPaneId: expandedDrawerParentPaneId
        )

        #expect(!enabled)
    }

    @Test("tab-level split capture enabled when management mode active and no drawer modal")
    func tabLevelSplitCaptureEnabledWithoutDrawerModal() {
        let enabled = TerminalSplitContainer.shouldEnableTabLevelSplitDropCapture(
            isManagementModeActive: true,
            expandedDrawerParentPaneId: nil
        )

        #expect(enabled)
    }

    @Test("background layout pane interactions suppressed while drawer modal active")
    func suppressBackgroundLayoutPaneInteractions() {
        let expandedDrawerParentPaneId = UUIDv7.generate()

        let suppressed = PaneLeafContainer.shouldSuppressBackgroundManagementInteractions(
            isManagementModeActive: true,
            expandedDrawerParentPaneId: expandedDrawerParentPaneId,
            paneDrawerParentPaneId: nil,
            useDrawerFramePreference: false
        )

        #expect(suppressed)
    }

    @Test("drawer modal foreground pane remains interactive")
    func drawerForegroundPaneRemainsInteractive() {
        let expandedDrawerParentPaneId = UUIDv7.generate()
        let drawerPaneParentPaneId = expandedDrawerParentPaneId

        let suppressed = PaneLeafContainer.shouldSuppressBackgroundManagementInteractions(
            isManagementModeActive: true,
            expandedDrawerParentPaneId: expandedDrawerParentPaneId,
            paneDrawerParentPaneId: drawerPaneParentPaneId,
            useDrawerFramePreference: true
        )

        #expect(!suppressed)
    }
}
