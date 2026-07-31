import AppKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioSharedComponents
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct ZoomPresentationContainerRenderStateTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("visible retained companion renders beside its source under one Zoom toolbar")
    func visibleRetainedCompanionUsesRuntimeSlotsAndParentToolbar() {
        let fixture = makeFixture()
        let viewerAction = makeAction(label: "Viewer", fixture: fixture) {
            fixture.recorder.recordViewer(sourcePaneId: $0)
        }
        let zoomAction = makeAction(label: "Pane Zoom", fixture: fixture) {
            fixture.recorder.recordZoom(sourcePaneId: $0)
        }
        let parentToolbar = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: .retainedVisible(companionPaneId: fixture.companionPaneId),
            viewerAction: viewerAction,
            zoomAction: zoomAction
        )

        guard
            let renderState = ZoomPresentationContainer.resolveRenderState(
                presentation: ZoomPresentation(
                    sourcePaneId: fixture.sourcePaneId,
                    viewerPresentation: .retainedVisible(companionPaneId: fixture.companionPaneId),
                    transientSplitRatio: 0.35
                ),
                viewRegistry: fixture.viewRegistry,
                parentToolbar: parentToolbar
            )
        else {
            Issue.record("Zoom container must resolve registered runtime hosts")
            return
        }

        #expect(renderState.layout.paneIds == [fixture.sourcePaneId, fixture.companionPaneId])
        #expect(renderState.layout.ratios == [0.35, 0.65])
        #expect(renderState.layout.dividerIds.count == 1)
        #expect(renderState.children.count == 2)
        #expect(renderState.isCompanionVisible)
        #expect(renderState.children.first?.paneId == fixture.sourcePaneId)
        #expect(renderState.children.last?.paneId == fixture.companionPaneId)
        #expect(renderState.children.allSatisfy { !$0.toolbarPresentation.reservesToolbarLayout })
        #expect(renderState.children.first?.paneSlot === fixture.sourcePaneSlot)
        #expect(renderState.children.last?.paneSlot === fixture.companionPaneSlot)
        #expect(renderState.children.first?.paneSlot.host === fixture.sourcePaneHost)
        #expect(renderState.children.last?.paneSlot.host === fixture.companionPaneHost)

        guard case .zoom(let toolbarModel) = renderState.parentToolbar else {
            Issue.record("Zoom container must own exactly one Zoom toolbar")
            return
        }
        #expect(toolbarModel.viewerAction.state.isEnabled)
        #expect(toolbarModel.viewerAction.state.isSelected)
        #expect(toolbarModel.zoomAction.state.isEnabled)
        #expect(toolbarModel.zoomAction.state.isSelected)
        #expect(toolbarModel.zoomAction.state.visibleLabel == "Zoomed")
        #expect(fixture.recorder.viewerSourcePaneIds.isEmpty)
        #expect(fixture.recorder.zoomSourcePaneIds.isEmpty)

        toolbarModel.zoomAction.perform()
        toolbarModel.viewerAction.perform()

        #expect(fixture.recorder.viewerSourcePaneIds == [fixture.sourcePaneId])
        #expect(fixture.recorder.zoomSourcePaneIds == [fixture.sourcePaneId])
    }

    @Test("hidden retained companion stays mounted for geometry animation with unselected Viewer")
    func hiddenRetainedCompanionStaysMounted() {
        let fixture = makeFixture()
        let viewerAction = makeAction(label: "Viewer", fixture: fixture) { _ in }
        let zoomAction = makeAction(label: "Pane Zoom", fixture: fixture) { _ in }
        let parentToolbar = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: .retainedHidden(companionPaneId: fixture.companionPaneId),
            viewerAction: viewerAction,
            zoomAction: zoomAction
        )

        guard
            let renderState = ZoomPresentationContainer.resolveRenderState(
                presentation: ZoomPresentation(
                    sourcePaneId: fixture.sourcePaneId,
                    viewerPresentation: .retainedHidden(companionPaneId: fixture.companionPaneId),
                    transientSplitRatio: 0.35
                ),
                viewRegistry: fixture.viewRegistry,
                parentToolbar: parentToolbar
            )
        else {
            Issue.record("Zoom container must resolve its registered source host")
            return
        }

        #expect(renderState.layout.paneIds == [fixture.sourcePaneId, fixture.companionPaneId])
        #expect(renderState.layout.ratios == [0.35, 0.65])
        #expect(renderState.layout.dividerIds.count == 1)
        #expect(renderState.children.count == 2)
        #expect(!renderState.isCompanionVisible)
        #expect(renderState.children.first?.paneId == fixture.sourcePaneId)
        #expect(renderState.children.last?.paneId == fixture.companionPaneId)
        #expect(renderState.children.first?.paneSlot === fixture.sourcePaneSlot)
        #expect(renderState.children.last?.paneSlot === fixture.companionPaneSlot)
        #expect(renderState.children.allSatisfy { !$0.toolbarPresentation.reservesToolbarLayout })

        guard case .zoom(let toolbarModel) = renderState.parentToolbar else {
            Issue.record("Zoom container must retain its parent Zoom toolbar")
            return
        }
        #expect(toolbarModel.viewerAction.state.isEnabled)
        #expect(!toolbarModel.viewerAction.state.isSelected)
        #expect(toolbarModel.zoomAction.state.isEnabled)
        #expect(toolbarModel.zoomAction.state.isSelected)
    }

    @Test("visible unavailable Viewer reserves its companion column without a Bridge host")
    func visibleUnavailableViewerReservesCompanionColumn() {
        let fixture = makeFixture()
        let viewerAction = makeAction(label: "Viewer", fixture: fixture) { _ in }
        let zoomAction = makeAction(label: "Pane Zoom", fixture: fixture) { _ in }
        let parentToolbar = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: .unavailableVisible,
            viewerAction: viewerAction,
            zoomAction: zoomAction
        )

        let renderState = ZoomPresentationContainer.resolveRenderState(
            presentation: ZoomPresentation(
                sourcePaneId: fixture.sourcePaneId,
                viewerPresentation: .unavailableVisible,
                transientSplitRatio: 0.35
            ),
            viewRegistry: fixture.viewRegistry,
            parentToolbar: parentToolbar
        )

        #expect(renderState?.children.map(\.paneId) == [fixture.sourcePaneId])
        #expect(renderState?.isCompanionVisible == true)
        #expect(renderState?.layout.paneIds == [fixture.sourcePaneId])
        guard case .zoom(let toolbarModel) = renderState?.parentToolbar else {
            Issue.record("Unavailable Viewer must retain the Zoom parent toolbar")
            return
        }
        #expect(toolbarModel.viewerAction.state.isEnabled)
        #expect(toolbarModel.viewerAction.state.isSelected)
    }

    private func makeFixture() -> ZoomPresentationContainerFixture {
        let sourcePaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let companionPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let viewRegistry = ViewRegistry()
        let sourcePaneHost = PaneHostView(paneId: sourcePaneId)
        let companionPaneHost = PaneHostView(paneId: companionPaneId)
        viewRegistry.register(sourcePaneHost, for: sourcePaneId)
        viewRegistry.register(companionPaneHost, for: companionPaneId)

        return ZoomPresentationContainerFixture(
            sourcePaneId: sourcePaneId,
            companionPaneId: companionPaneId,
            viewRegistry: viewRegistry,
            sourcePaneSlot: viewRegistry.slot(for: sourcePaneId),
            companionPaneSlot: viewRegistry.slot(for: companionPaneId),
            sourcePaneHost: sourcePaneHost,
            companionPaneHost: companionPaneHost,
            recorder: ZoomPresentationContainerActionRecorder()
        )
    }

    private func makeAction(
        label: String,
        fixture: ZoomPresentationContainerFixture,
        perform: @MainActor @Sendable @escaping (UUID) -> Void
    ) -> PaneSurfaceToolbarAction {
        let sourcePaneId = fixture.sourcePaneId
        return PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: label,
                accessibilityIdentifier: "paneSurfaceToolbar.\(label == "Pane Zoom" ? "zoom" : label.lowercased())",
                icon: .system(label == "Viewer" ? .rectangleSplit2x1 : .plusMagnifyingglass),
                tooltip: ControlTooltipRenderValue(text: label, shortcutDisplayText: nil),
                isEnabled: true,
                isSelected: false
            ),
            perform: {
                perform(sourcePaneId)
            }
        )
    }
}
