import Foundation
import Testing

@Suite("DrawerTabLevelCaptureArchitectureTests")
struct DrawerTabLevelCaptureArchitectureTests {
    private struct Sources {
        let flatTabStripContainer: String
        let drawerPanel: String
        let drawerPanelOverlay: String
        let paneTabViewController: String
        let paneTabDropPlanning: String
        let drawerGridLayoutRearrange: String
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
            ),
            paneTabViewController: String(
                contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Panes/PaneTabViewController.swift"),
                encoding: .utf8
            ),
            paneTabDropPlanning: optionalSource(
                projectRoot.appending(path: "Sources/AgentStudio/App/Panes/PaneTabViewController+DropPlanning.swift")
            ),
            drawerGridLayoutRearrange: String(
                contentsOf: projectRoot.appending(
                    path: "Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift"),
                encoding: .utf8
            )
        )
    }

    private func optionalSource(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
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

    @Test("main split capture is not mounted while drawer capture owns drag routing")
    func mainSplitCapture_isConditionallyMountedOnlyWhenEnabled() throws {
        let sources = try loadSources()
        let captureRange = try #require(sources.flatTabStripContainer.range(of: "SplitContainerDropCaptureOverlay("))
        let prefix = sources.flatTabStripContainer[..<captureRange.lowerBound]
        // Window is widened (1200 chars) to tolerate intervening helper
        // declarations between the policy gate and the capture mount —
        // e.g., let-bindings that resolve drop visuals from the active
        // target before constructing the overlay views.
        let recentContext = prefix.suffix(1200)

        #expect(recentContext.contains("if managementLayer.isActive && mainSplitDragCaptureEnabled"))
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

    @Test("drawer overlay does not apply a clip mask above AppKit drag capture")
    func drawerPanelOverlay_doesNotClipCaptureAncestorPath() throws {
        let sources = try loadSources()

        #expect(!sources.drawerPanelOverlay.contains(".clipShape(outlineShape)"))
    }

    @Test("drawer rearrange has no legacy pane-drop planning path")
    func drawerRearrange_hasSingleTabLevelPlanningPath() throws {
        let sources = try loadSources()

        #expect(!sources.paneTabViewController.contains("drawerMoveDropAction("))
        #expect(!sources.paneTabDropPlanning.contains("resolveDrawerMoveDropAction("))
        #expect(!sources.drawerGridLayoutRearrange.contains("legacyMoveTarget("))
    }
}
