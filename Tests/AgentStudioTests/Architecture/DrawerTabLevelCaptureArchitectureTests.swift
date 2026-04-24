import Foundation
import Testing

@Suite("DrawerTabLevelCaptureArchitectureTests")
struct DrawerTabLevelCaptureArchitectureTests {
    private struct Sources {
        let flatTabStripContainer: String
        let drawerPanel: String
        let drawerPanelOverlay: String
    }

    private func loadSources() throws -> Sources {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try Sources(
            flatTabStripContainer: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift"),
                encoding: .utf8
            ),
            drawerPanel: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift"),
                encoding: .utf8
            ),
            drawerPanelOverlay: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift"),
                encoding: .utf8
            )
        )
    }

    @Test("drawer drag capture is mounted at tab level, not inside DrawerPanel")
    func drawerDragCapture_isTabLevelOnly() throws {
        let sources = try loadSources()

        #expect(sources.flatTabStripContainer.contains("tabLevelDrawerCapture(expandedDrawerParentPaneId:"))
        #expect(sources.flatTabStripContainer.contains("DrawerSplitContainerDropCaptureOverlay("))
        #expect(sources.flatTabStripContainer.contains("DrawerDropDispatch.shouldAcceptDrop("))
        #expect(sources.flatTabStripContainer.contains("DrawerDropDispatch.handleDrop("))
        #expect(!sources.drawerPanel.contains("DrawerSplitContainerDropCaptureOverlay("))
    }

    @Test("drawer panel only renders tab-level drop target state")
    func drawerPanel_rendersExternallyOwnedDropTarget() throws {
        let sources = try loadSources()

        #expect(sources.drawerPanel.contains("let dropTarget: DrawerRearrangeTarget?"))
        #expect(sources.drawerPanelOverlay.contains("let drawerDropTarget: DrawerRearrangeTarget?"))
        #expect(sources.drawerPanelOverlay.contains("dropTarget: drawerDropTarget"))
        #expect(sources.flatTabStripContainer.contains("@State private var drawerDropTarget: DrawerRearrangeTarget?"))
    }

    @Test("drawer panel reports panel-only tab frame and overlay has no SwiftUI dismiss scrim")
    func drawerPanel_reportsPanelOnlyTabFrameWithoutOverlayScrim() throws {
        let sources = try loadSources()

        #expect(sources.drawerPanelOverlay.contains("struct DrawerPanelFrameInTabKey: PreferenceKey"))
        #expect(sources.drawerPanel.contains("key: DrawerPanelFrameInTabKey.self"))
        #expect(!sources.drawerPanelOverlay.contains("key: DrawerPanelFrameInTabKey.self"))
        #expect(sources.flatTabStripContainer.contains(".onPreferenceChange(DrawerPanelFrameInTabKey.self)"))
        #expect(!sources.drawerPanelOverlay.contains("OutsideDismissShape"))
        #expect(!sources.drawerPanelOverlay.contains("Color.black.opacity(0.001)"))
    }
}
