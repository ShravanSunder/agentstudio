import AgentStudioInfrastructure
import AppKit
import SwiftUI
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("DrawerOverlay icon bar visibility")
struct DrawerOverlayIconBarVisibilityTests {
    @Test("hidden icon bar is structurally absent while visible icon bar is mounted")
    func iconBarVisibilityControlsStructure() throws {
        let visibleMount = mountDrawerOverlay(isIconBarVisible: true)
        defer {
            visibleMount.window.orderOut(nil)
            visibleMount.window.close()
        }

        #expect(visibleMount.hostingView.fittingSize.height > 0)
        let visibleProbe = try #require(
            findView(
                in: visibleMount.hostingView,
                identifier: Self.probeAccessibilityIdentifier
            )
        )
        #expect(visibleProbe.isAccessibilityElement())
        #expect(visibleProbe.accessibilityLabel() == Self.probeAccessibilityLabel)
        #expect(
            visibleProbe.hitTest(
                NSPoint(x: visibleProbe.bounds.midX, y: visibleProbe.bounds.midY)
            ) != nil
        )

        let hiddenMount = mountDrawerOverlay(isIconBarVisible: false)
        defer {
            hiddenMount.window.orderOut(nil)
            hiddenMount.window.close()
        }

        #expect(hiddenMount.hostingView.fittingSize.height == 0)
        #expect(
            findView(
                in: hiddenMount.hostingView,
                identifier: Self.probeAccessibilityIdentifier
            ) == nil
        )
        #expect(
            findAccessibleElement(
                in: hiddenMount.hostingView,
                identifier: Self.probeAccessibilityIdentifier
            ) == nil
        )
    }

    @Test("pane mode precedes adjacent uniform Drawer controls")
    func toolbarControlOrderAndDrawerSpacing() throws {
        let mount = mountDrawerOverlay(isIconBarVisible: true)
        defer {
            mount.window.orderOut(nil)
            mount.window.close()
        }

        let paneModeView = try #require(
            findView(
                in: mount.hostingView,
                identifier: Self.probeAccessibilityIdentifier
            )
        )
        let drawerToggleView = try #require(
            findView(
                in: mount.hostingView,
                identifier: "paneSurfaceToolbar.drawerToggle"
            )
        )
        let drawerAddView = try #require(
            findView(
                in: mount.hostingView,
                identifier: "paneSurfaceToolbar.drawerAdd"
            )
        )
        let paneModeFrame = paneModeView.convert(paneModeView.bounds, to: mount.hostingView)
        let drawerToggleFrame = drawerToggleView.convert(drawerToggleView.bounds, to: mount.hostingView)
        let drawerAddFrame = drawerAddView.convert(drawerAddView.bounds, to: mount.hostingView)

        #expect(paneModeFrame.maxX < drawerToggleFrame.minX)
        #expect(drawerToggleFrame.maxX < drawerAddFrame.minX)
        #expect(paneModeFrame.size == drawerToggleFrame.size)
        #expect(drawerToggleFrame.size == drawerAddFrame.size)
        #expect(paneModeFrame.width == DrawerLayout.iconButtonSize)
        #expect(paneModeFrame.height == DrawerLayout.iconButtonSize)
        #expect(drawerToggleFrame.width == DrawerLayout.iconButtonSize)
        #expect(drawerToggleFrame.height == DrawerLayout.iconButtonSize)
        #expect(
            abs(
                drawerToggleFrame.minX - paneModeFrame.maxX
                    - expectedToolbarSeparatorWidth
            ) < 0.5
        )
        #expect(
            abs(
                drawerAddFrame.minX - drawerToggleFrame.maxX
                    - AppStyles.Shell.DrawerToolbar.trailingClusterSpacing
            ) < 0.5
        )
    }

    @Test("Zoom toolbar orders pane mode, Drawer, Viewer, Editor, location, then alerts")
    func zoomToolbarUsesAcceptedSemanticGroupOrder() throws {
        let zoomAction = makePaneSurfaceAction(
            label: "Pane Zoom",
            identifier: "paneSurfaceToolbar.zoom"
        )
        let viewerAction = makePaneSurfaceAction(
            label: "Viewer",
            identifier: "paneSurfaceToolbar.viewer"
        )
        let mount = mountDrawerOverlay(
            isIconBarVisible: true,
            trailingActions: makeTrailingActions(),
            paneSurfaceActions: [],
            paneContextActions: [zoomAction, viewerAction],
            width: 720
        )
        defer {
            mount.window.orderOut(nil)
            mount.window.close()
        }

        let orderedIdentifiers = [
            "paneSurfaceToolbar.drawerToggle",
            "paneSurfaceToolbar.drawerAdd",
            "paneSurfaceToolbar.zoom",
            "paneSurfaceToolbar.viewer",
            "paneSurfaceToolbar.editor",
            "paneSurfaceToolbar.finder",
            "paneSurfaceToolbar.copyPath",
            "paneSurfaceToolbar.inbox",
        ]
        let orderedFrames = try orderedIdentifiers.map { identifier in
            let view = try #require(findView(in: mount.hostingView, identifier: identifier))
            return view.convert(view.bounds, to: mount.hostingView)
        }

        for (leftFrame, rightFrame) in zip(orderedFrames, orderedFrames.dropFirst()) {
            #expect(leftFrame.maxX < rightFrame.minX)
        }
    }

    @Test("PR action precedes the separator before pane fullscreen controls")
    func pullRequestActionPrecedesPaneContextActions() throws {
        let zoomAction = makePaneSurfaceAction(
            label: "Pane Zoom",
            identifier: "paneSurfaceToolbar.zoom"
        )
        let pullRequestAction = makePaneSurfaceAction(
            label: "Open PR",
            identifier: "paneSurfaceToolbar.pullRequest"
        )
        let mount = mountDrawerOverlay(
            isIconBarVisible: true,
            trailingActions: makeTrailingActions(openPullRequestAction: pullRequestAction),
            paneContextActions: [zoomAction],
            width: 640
        )
        defer {
            mount.window.orderOut(nil)
            mount.window.close()
        }

        let orderedIdentifiers = [
            "paneSurfaceToolbar.drawerToggle",
            "paneSurfaceToolbar.drawerAdd",
            "paneSurfaceToolbar.pullRequest",
            "paneSurfaceToolbar.zoom",
            "paneSurfaceToolbar.editor",
        ]
        let orderedFrames = try orderedIdentifiers.map { identifier in
            let view = try #require(findView(in: mount.hostingView, identifier: identifier))
            return view.convert(view.bounds, to: mount.hostingView)
        }

        for (leftFrame, rightFrame) in zip(orderedFrames, orderedFrames.dropFirst()) {
            #expect(leftFrame.maxX < rightFrame.minX)
        }
    }

    @Test("toolbar group separators use standard horizontal spacing")
    func toolbarGroupSeparatorsUseStandardHorizontalSpacing() throws {
        let mount = mountDrawerOverlay(isIconBarVisible: true)
        defer {
            mount.window.orderOut(nil)
            mount.window.close()
        }

        let paneModeView = try #require(
            findView(in: mount.hostingView, identifier: Self.probeAccessibilityIdentifier)
        )
        let drawerToggleView = try #require(
            findView(in: mount.hostingView, identifier: "paneSurfaceToolbar.drawerToggle")
        )
        let paneModeFrame = paneModeView.convert(paneModeView.bounds, to: mount.hostingView)
        let drawerToggleFrame = drawerToggleView.convert(drawerToggleView.bounds, to: mount.hostingView)
        let standardSeparatorWidth = (AppStyles.General.Spacing.standard * 2) + 1

        #expect(
            abs(drawerToggleFrame.minX - paneModeFrame.maxX - standardSeparatorWidth) < 0.5
        )
    }

    @Test("absent pane mode does not leave an empty leading separator")
    func absentPaneModeDoesNotLeaveEmptyLeadingSeparator() throws {
        let mount = mountDrawerOverlay(
            isIconBarVisible: true,
            paneSurfaceActions: []
        )
        defer {
            mount.window.orderOut(nil)
            mount.window.close()
        }

        let drawerToggleView = try #require(
            findView(
                in: mount.hostingView,
                identifier: "paneSurfaceToolbar.drawerToggle"
            )
        )
        let drawerToggleFrame = drawerToggleView.convert(
            drawerToggleView.bounds,
            to: mount.hostingView
        )

        #expect(
            abs(drawerToggleFrame.minX - DrawerLayout.iconBarVerticalPadding) < 0.5
        )
    }

    private static let probeAccessibilityLabel = "VisibilityProbe"
    private static let probeAccessibilityIdentifier = "paneSurfaceToolbar.visibilityprobe"

    private var expectedToolbarSeparatorWidth: CGFloat {
        (AppStyles.Shell.DrawerToolbar.dividerHorizontalPadding * 2) + 1
    }

    private func mountDrawerOverlay(
        isIconBarVisible: Bool,
        trailingActions: DrawerOverlay.TrailingActions? = nil,
        paneSurfaceActions: [PaneSurfaceToolbarAction]? = nil,
        paneContextActions: [PaneSurfaceToolbarAction] = [],
        width: CGFloat = 360
    ) -> DrawerOverlayMount {
        let probeAction = PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: Self.probeAccessibilityLabel,
                accessibilityIdentifier: Self.probeAccessibilityIdentifier,
                icon: .system(.rectangleSplit2x1),
                tooltip: ControlTooltipRenderValue(
                    text: "Visibility probe",
                    shortcutDisplayText: nil
                ),
                isEnabled: true,
                isSelected: false
            ),
            perform: {}
        )
        let hostingView = NSHostingView<AnyView>(
            rootView: AnyView(
                DrawerOverlay(
                    octiconLoader: makeCoreTestOcticonLoader(),
                    drawer: nil,
                    isIconBarVisible: isIconBarVisible,
                    toggleDrawerAction: makeTargetedAction(.toggleDrawer),
                    addDrawerPaneAction: makeTargetedAction(.addDrawerPane),
                    trailingActions: trailingActions,
                    paneSurfaceActions: paneSurfaceActions ?? [probeAction],
                    paneContextActions: paneContextActions
                )
                .frame(width: width)
            )
        )
        hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()

        return DrawerOverlayMount(hostingView: hostingView, window: window)
    }

    private func makeTrailingActions(
        openPullRequestAction: PaneSurfaceToolbarAction? = nil
    ) -> DrawerOverlay.TrailingActions {
        DrawerOverlay.TrailingActions(
            openEditorMenuAction: makeTargetedAction(.openPaneLocationInEditorMenu),
            openFinderAction: makeTargetedAction(.openPaneLocationInFinder),
            copyPathAction: makeTargetedAction(.copyCurrentPanePath),
            openPullRequestAction: openPullRequestAction,
            showPaneInboxAction: makeTargetedAction(.showPaneInboxNotifications),
            editorMenuContent: AnyView(EmptyView()),
            editorMenuPresented: .constant(false),
            buttonTitle: nil,
            inboxPopoverContent: AnyView(EmptyView())
        )
    }

    private func makeTargetedAction(
        _ command: AppCommand
    ) -> TargetedCommandControlAction {
        TargetedCommandControlAction(
            commandSpec: command.definition,
            isEnabled: true,
            perform: {}
        )
    }

    private func makePaneSurfaceAction(
        label: String,
        identifier: String
    ) -> PaneSurfaceToolbarAction {
        PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: label,
                accessibilityIdentifier: identifier,
                icon: .system(.rectangleSplit2x1),
                tooltip: ControlTooltipRenderValue(
                    text: label,
                    shortcutDisplayText: nil
                ),
                isEnabled: true,
                isSelected: false
            ),
            perform: {}
        )
    }
}

@MainActor
private struct DrawerOverlayMount {
    let hostingView: NSHostingView<AnyView>
    let window: NSWindow
}

@MainActor
private func findView(in root: NSView, identifier: String) -> NSView? {
    if root.identifier?.rawValue == identifier {
        return root
    }

    for subview in root.subviews {
        if let match = findView(in: subview, identifier: identifier) {
            return match
        }
    }

    return nil
}

@MainActor
private func findAccessibleElement(in root: AnyObject, identifier: String) -> AnyObject? {
    var visited: Set<ObjectIdentifier> = []
    return findAccessibleElement(
        in: root,
        identifier: identifier,
        visited: &visited
    )
}

@MainActor
private func findAccessibleElement(
    in element: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> AnyObject? {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return nil }

    if element.accessibilityIdentifier?() == identifier {
        return element
    }

    for child in (element.accessibilityChildren?() ?? []).compactMap({ $0 as? NSObject }) {
        if let match = findAccessibleElement(
            in: child,
            identifier: identifier,
            visited: &visited
        ) {
            return match
        }
    }

    return nil
}
