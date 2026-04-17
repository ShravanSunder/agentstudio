import Testing

@testable import AgentStudio

@MainActor
@Suite("CollapsedPaneBar")
struct CollapsedPaneBarTests {
    @Test("exposes expand as the only primary action button")
    func exposesOnlyExpandButton() {
        #expect(CollapsedPaneBar.primaryButtonIdentifiers == [.expand])
    }

    @Test("does not expose an arrangement-popover button")
    func doesNotExposeArrangementButton() {
        #expect(!CollapsedPaneBar.primaryButtonIdentifiers.contains(.arrangementPopover))
    }
}
