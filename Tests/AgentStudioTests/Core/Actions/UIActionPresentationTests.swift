import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct UIActionPresentationTests {
    @Test
    func detachDrawerPaneActionSpec_hasStableLabelAndIcon() {
        let spec = LocalActionSpec.detachDrawerPane.actionSpec

        #expect(spec.label == "Detach Drawer Pane")
        #expect(spec.helpText == "Move this drawer pane into the parent tab on the right")
        #expect(spec.icon == .system("arrow.up.right.square"))
    }
}
