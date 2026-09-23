import AppKit
import SwiftUI
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInfrastructure
@testable import AgentStudioSharedComponents
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct ZoomPresentationContainerGeometryTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("Zoom management identity spans the full content above the toolbar")
    func zoomManagementIdentitySpansFullContentAboveToolbar() throws {
        let frames = mountedZoomManagementRegionFrames()
        let identityFrame = try #require(frames["paneManagement.identityStrip"])
        let sourceFrame = try #require(frames["zoom-source-region-probe"])
        let companionFrame = try #require(frames["zoom-companion-region-probe"])
        let toolbarFrame = try #require(frames["paneSurfaceToolbar.pane zoom"])

        #expect(identityFrame.maxX > companionFrame.minX)
        #expect(
            abs(
                companionFrame.maxX - identityFrame.maxX
                    - AppStyles.General.Spacing.loose
            ) < 0.5
        )
        #expect(identityFrame.maxY <= toolbarFrame.minY)
        #expect(abs(sourceFrame.height - companionFrame.height) < 0.5)
    }

    @Test("Zoom drawer outline sits on the terminal region bottom with no footer gap and no resize target")
    func zoomDrawerOutlineSitsOnTerminalRegionBottom() throws {
        let frames = try mountedZoomDrawerFrames(zoomSide: .terminal)
        let outline = try #require(frames.outline)
        let region = frames.terminalRegion
        // The split area ends where the shared toolbar begins, so the complete
        // outline sitting on the region bottom leaves no gap above the toolbar.
        #expect(abs(outline.maxY - region.maxY) < 0.5)
        #expect(outline.maxY <= frames.zoomToolbarButton.minY)
        // Upper 15% of the region stays exposed; 97% of its width, centered.
        #expect(abs(outline.minY - (region.minY + region.height * 0.15)) < 0.5)
        #expect(abs(outline.width - region.width * 0.97) < 0.5)
        #expect(abs(outline.midX - region.midX) < 0.5)
        #expect(frames.hasResizeHandle == false)
    }

    @Test("Zoom drawer moved to Bridge fits the unequal Bridge region")
    func zoomDrawerOutlineFitsBridgeRegion() throws {
        let frames = try mountedZoomDrawerFrames(zoomSide: .bridge)
        let outline = try #require(frames.outline)
        let region = frames.bridgeRegion

        #expect(abs(outline.maxY - region.maxY) < 0.5)
        #expect(abs(outline.width - region.width * 0.97) < 0.5)
        #expect(abs(outline.midX - region.midX) < 0.5)
        #expect(outline.minX > region.minX)
        #expect(outline.maxX < region.maxX)
    }

    @Test("Zoom drawer paint and bootstrap resolve the same outline for the same input")
    func zoomDrawerPaintMatchesBootstrapGeometry() throws {
        for side in DrawerZoomSide.allCases {
            let frames = try mountedZoomDrawerFrames(zoomSide: side)
            let painted = try #require(frames.outline)
            // Bootstrap derives the split area from the container and the
            // shared toolbar metric, never from SwiftUI measurement.
            let regions = DrawerPresentationGeometryResolver.zoomRegions(
                splitArea: CGRect(x: 0, y: 0, width: 1000, height: 640 - DrawerLayout.iconBarFrameHeight),
                sourceSplitRatio: 0.7,
                reservesCompanionSpace: true,
                isCompanionVisible: true
            )
            let bootstrap = try #require(
                DrawerPresentationGeometryResolver.resolve(
                    DrawerPresentationGeometryInput(
                        containerBounds: CGRect(x: 0, y: 0, width: 1000, height: 640),
                        preference: DrawerPresentationPreference.default.replacingZoomSide(side),
                        placement: .zoom(terminalRegion: regions.terminal, visibleBridgeRegion: regions.bridge)
                    )
                )
            )
            #expect(abs(painted.minX - bootstrap.outlineFrame.minX) < 0.5, "\(side)")
            #expect(abs(painted.minY - bootstrap.outlineFrame.minY) < 0.5, "\(side)")
            #expect(abs(painted.width - bootstrap.outlineFrame.width) < 0.5, "\(side)")
            #expect(abs(painted.height - bootstrap.outlineFrame.height) < 0.5, "\(side)")
        }
    }

    private struct MountedZoomDrawerFrames {
        let outline: CGRect?
        let terminalRegion: CGRect
        let bridgeRegion: CGRect
        let zoomToolbarButton: CGRect
        let hasResizeHandle: Bool
    }

    private func mountedZoomDrawerFrames(zoomSide: DrawerZoomSide) throws -> MountedZoomDrawerFrames {
        try withTestCoreAtoms { coreAtoms in
            let store = WorkspaceStore(
                identityAtom: coreAtoms.workspaceIdentity,
                windowMemoryAtom: coreAtoms.workspaceWindowMemory,
                repositoryTopologyAtom: coreAtoms.workspaceRepositoryTopology,
                paneAtom: coreAtoms.workspacePane,
                tabLayoutAtom: coreAtoms.workspaceTabLayout,
                mutationCoordinator: coreAtoms.workspaceMutationCoordinator,
                startsObserving: false
            )
            let sourcePane = store.createPane()
            let tab = Tab(paneId: sourcePane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let drawerChild = try #require(store.addDrawerPane(to: sourcePane.id))
            let viewRegistry = ViewRegistry()
            viewRegistry.ensureSlot(for: drawerChild.id)
            #expect(store.paneAtom.pane(sourcePane.id)?.drawer?.isExpanded == true)
            store.paneAtom.setDrawerZoomSide(zoomSide, forOwner: sourcePane.id)
            let companionPaneId = UUIDv7.generate()

            let hostingView = NSHostingView(
                rootView: ZoomPresentationContainer(
                    tabId: tab.id,
                    sourcePaneId: sourcePane.id,
                    sourceOrdinal: 1,
                    sourceContent: AnyView(
                        Color.clear.background {
                            AccessibilityLabelBridge(identifier: "zoom-source-region-probe", label: "Source")
                        }
                    ),
                    companionContent: AnyView(
                        Color.clear.background {
                            AccessibilityLabelBridge(identifier: "zoom-companion-region-probe", label: "Companion")
                        }
                    ),
                    parentToolbarPresentation: .zoom(
                        ZoomToolbarModel(
                            viewerAction: probeAction(label: "Viewer"),
                            zoomAction: probeAction(label: "Pane Zoom")
                        )
                    ),
                    splitRatio: 0.7,
                    store: store,
                    octiconLoader: makeTestOcticonLoader(),
                    editorChooser: makeTestAtomRegistry().editorChooser,
                    actionDispatcher: makeNoOpPaneActionDispatcher(),
                    arrangementInlineRenameState: ArrangementInlineRenameState(),
                    onPaneFocusTrigger: { _ in },
                    viewRegistry: viewRegistry,
                    surfaceId: "zoom-drawer-geometry-test",
                    renderedPaneIds: [sourcePane.id, companionPaneId]
                )
                .frame(width: 1000, height: 640)
            )
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer {
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
            // The first pass measures the split area; the second lays the
            // overlay out from those measured regions.
            hostingView.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()

            @MainActor func frame(_ identifier: String) -> CGRect? {
                findView(in: hostingView, identifier: identifier).map { view in
                    view.convert(view.bounds, to: hostingView)
                }
            }
            return MountedZoomDrawerFrames(
                outline: frame(DrawerPanelOverlay.outlineAccessibilityIdentifier),
                terminalRegion: try #require(frame("zoom-source-region-probe")),
                bridgeRegion: try #require(frame("zoom-companion-region-probe")),
                zoomToolbarButton: try #require(frame("paneSurfaceToolbar.pane zoom")),
                hasResizeHandle: frame(DrawerResizeHandle.accessibilityIdentifier) != nil
            )
        }
    }

    private func mountedZoomManagementRegionFrames() -> [String: CGRect] {
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/agent-studio"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature-name",
            path: URL(filePath: "/tmp/agent-studio/feature-name")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
        let storedWorktree = store.repos[0].worktrees[0]
        let sourcePane = store.createPane(
            launchDirectory: storedWorktree.path,
            facets: PaneContextFacets(
                repoId: repo.id,
                repoName: repo.name,
                worktreeId: storedWorktree.id,
                worktreeName: storedWorktree.name,
                cwd: storedWorktree.path
            )
        )
        let companionPaneId = UUIDv7.generate()
        let viewRegistry = ViewRegistry()
        let hostingView = NSHostingView(
            rootView: ZoomPresentationContainer(
                sourcePaneId: sourcePane.id,
                sourceOrdinal: 1,
                sourceContent: AnyView(
                    Color.clear.background {
                        AccessibilityLabelBridge(
                            identifier: "zoom-source-region-probe",
                            label: "Source"
                        )
                    }
                ),
                companionContent: AnyView(
                    Color.clear.background {
                        AccessibilityLabelBridge(
                            identifier: "zoom-companion-region-probe",
                            label: "Companion"
                        )
                    }
                ),
                parentToolbarPresentation: .zoom(
                    ZoomToolbarModel(
                        viewerAction: probeAction(label: "Viewer"),
                        zoomAction: probeAction(label: "Pane Zoom")
                    )
                ),
                splitRatio: 0.35,
                store: store,
                octiconLoader: makeTestOcticonLoader(),
                editorChooser: makeTestAtomRegistry().editorChooser,
                actionDispatcher: makeNoOpPaneActionDispatcher(),
                arrangementInlineRenameState: ArrangementInlineRenameState(),
                onPaneFocusTrigger: { _ in },
                viewRegistry: viewRegistry,
                surfaceId: "zoom-management-identity-geometry-test",
                renderedPaneIds: [sourcePane.id, companionPaneId]
            )
            .frame(width: 640, height: 360)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        atom(\.managementLayer).activate()
        window.makeKeyAndOrderFront(nil)
        defer {
            atom(\.managementLayer).deactivate()
            window.orderOut(nil)
            window.close()
        }

        hostingView.layoutSubtreeIfNeeded()

        return Dictionary(
            uniqueKeysWithValues: [
                "paneManagement.identityStrip",
                "zoom-source-region-probe",
                "zoom-companion-region-probe",
                "paneSurfaceToolbar.pane zoom",
            ].compactMap { identifier in
                guard let view = findView(in: hostingView, identifier: identifier) else {
                    return nil
                }
                return (identifier, view.convert(view.bounds, to: hostingView))
            }
        )
    }

    private func probeAction(label: String) -> PaneSurfaceToolbarAction {
        PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: label,
                accessibilityIdentifier: "paneSurfaceToolbar.\(label.lowercased())",
                icon: .system(.rectangleSplit2x1),
                tooltip: ControlTooltipRenderValue(text: label, shortcutDisplayText: nil),
                isEnabled: true,
                isSelected: false
            ),
            perform: {}
        )
    }

    private func makeNoOpPaneActionDispatcher() -> PaneTabActionDispatcher {
        PaneTabActionDispatcher(
            dispatch: { _ in },
            shouldHandleSplitDragPayload: { _ in false },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )
    }

    private func findView(in root: NSView, identifier: String) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let matchingView = findView(in: subview, identifier: identifier) {
                return matchingView
            }
        }
        return nil
    }
}
