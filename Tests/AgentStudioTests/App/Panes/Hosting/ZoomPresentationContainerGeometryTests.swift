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

    @Test("Zoom management identity stays inside the source column")
    func zoomManagementIdentityStaysInsideSourceColumn() throws {
        let frames = mountedZoomManagementRegionFrames()
        let identityFrame = try #require(frames["paneManagement.identityStrip"])
        let companionFrame = try #require(frames["zoom-companion-region-probe"])

        #expect(identityFrame.maxX <= companionFrame.minX + 0.5)
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
