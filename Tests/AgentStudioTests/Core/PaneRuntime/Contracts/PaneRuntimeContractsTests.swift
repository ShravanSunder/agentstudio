import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneRuntime contracts")
struct PaneRuntimeContractsTests {
    @Test("terminal events expose action policy")
    func terminalPolicy() {
        let event = PaneRuntimeEvent.terminal(.bellRang)
        #expect(event.actionPolicy == .critical)
    }

    @Test("runtime command namespace is distinct from workspace PaneAction")
    func commandTypeIsDistinct() {
        let command = PaneCommand.activate
        #expect(String(describing: command).contains("activate"))
    }

    @Test("pane metadata remains available after relocation to pane runtime contracts")
    func paneMetadataRelocation() {
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "X"), title: "X")
        #expect(metadata.title == "X")
    }
}
