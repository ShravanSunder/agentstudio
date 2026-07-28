import Testing

@testable import AgentStudio

struct MinimizedPaneBarPresentationTests {
    @Test(
        "minimized bars render for either Management or Arrangements",
        arguments: [
            (managementLayerActive: false, arrangementPanelPresented: false, expected: false),
            (managementLayerActive: true, arrangementPanelPresented: false, expected: true),
            (managementLayerActive: false, arrangementPanelPresented: true, expected: true),
            (managementLayerActive: true, arrangementPanelPresented: true, expected: true),
        ]
    )
    func minimizedBarsRenderForEitherPresentationSurface(
        managementLayerActive: Bool,
        arrangementPanelPresented: Bool,
        expected: Bool
    ) {
        let presentation = MinimizedPaneBarPresentation(
            managementLayerActive: managementLayerActive,
            arrangementPanelPresented: arrangementPanelPresented
        )

        #expect(presentation.rendersBars == expected)
    }
}
