import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("PaneTabViewController toolbar presentation", .serialized)
struct PaneTabViewControllerToolbarPresentationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("Viewer is absent from a normal pane and available in terminal Zoom")
    func normalPaneAndTerminalZoomFactoriesRemainDistinct() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let sourcePane = harness.store.createPane()
        let tab = Tab(paneId: sourcePane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(sourcePane.id, inTab: tab.id)
        atom(\.workspaceFocusOwner).focusMainPane(sourcePane.id)

        let normalPanePresentation =
            harness.controller.normalPaneSurfaceToolbarPresentation(for: sourcePane.id)

        harness.store.panePresentationAtom.enterZoom(
            inTab: tab.id,
            sourcePaneId: sourcePane.id,
            viewerPresentation: .retryable
        )
        let terminalZoomPresentation =
            harness.controller.zoomPaneSurfaceToolbarPresentation(
                for: sourcePane.id,
                viewerPresentation: .retryable
            )

        #expect(
            normalPanePresentation.contextActions.map(\.state.label) == [
                AppCommand.zoomPane.definition.label
            ]
        )
        #expect(normalPanePresentation.contextActions.allSatisfy { !$0.state.isSelected })
        #expect(
            terminalZoomPresentation.contextActions.map(\.state.label) == [
                AppCommand.zoomPane.definition.label,
                AppCommand.showViewer.definition.label,
            ]
        )
        #expect(terminalZoomPresentation.zoomAction?.state.isSelected == true)
        #expect(
            terminalZoomPresentation.contextActions.first {
                $0.state.label == AppCommand.showViewer.definition.label
            }?.state.isSelected == false
        )
    }
}
