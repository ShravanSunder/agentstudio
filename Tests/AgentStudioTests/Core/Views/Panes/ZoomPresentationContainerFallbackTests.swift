import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ZoomPresentationContainerFallbackTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("missing retained companion host falls back to source-only Zoom")
    func missingRetainedCompanionHostRendersSourceOnly() throws {
        let sourcePaneId = UUID()
        let companionPaneId = UUID()
        let sourcePaneHost = PaneHostView(paneId: sourcePaneId)
        let viewRegistry = ViewRegistry()
        viewRegistry.register(sourcePaneHost, for: sourcePaneId)
        viewRegistry.ensureSlot(for: companionPaneId)

        let parentToolbar = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: .retainedVisible(companionPaneId: companionPaneId),
            viewerAction: makeAction(label: "Viewer"),
            zoomAction: makeAction(label: "Pane Zoom")
        )
        let renderState = try #require(
            ZoomPresentationContainer.resolveRenderState(
                presentation: ZoomPresentation(
                    sourcePaneId: sourcePaneId,
                    viewerPresentation: .retainedVisible(companionPaneId: companionPaneId),
                    transientSplitRatio: 0.35
                ),
                viewRegistry: viewRegistry,
                parentToolbar: parentToolbar
            )
        )

        #expect(renderState.layout.paneIds == [sourcePaneId])
        #expect(renderState.children.map(\.paneId) == [sourcePaneId])
        #expect(renderState.children[0].paneSlot.host === sourcePaneHost)
        #expect(!renderState.isCompanionVisible)
        #expect(renderState.parentToolbar.zoomAction != nil)
    }

    private func makeAction(label: String) -> PaneSurfaceToolbarAction {
        PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: label,
                accessibilityIdentifier: "paneSurfaceToolbar.\(label)",
                icon: .system(.rectangleSplit2x1),
                tooltip: ControlTooltipRenderValue(text: label, shortcutDisplayText: nil),
                isEnabled: true,
                isSelected: false
            ),
            perform: {}
        )
    }
}
