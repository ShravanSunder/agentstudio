import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct UIActionPresentationTests {
    @Test
    func detachDrawerPaneCommandDefinition_hasStablePresentation() {
        let definition = CommandDispatcher.shared.definition(for: .detachDrawerPane)

        #expect(definition.label == "Detach Drawer Pane")
        #expect(definition.helpText == "Promote the selected drawer pane into the main layout")
        #expect(definition.icon == "rectangle.portrait.and.arrow.right")
    }
}
