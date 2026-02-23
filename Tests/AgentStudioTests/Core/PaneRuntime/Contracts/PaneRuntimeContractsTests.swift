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
        let command = RuntimeCommand.activate
        #expect(String(describing: command).contains("activate"))
    }

    @Test("event identifier supports built-in and plugin tags")
    func eventIdentifierExtensibility() {
        #expect(EventIdentifier.commandFinished.rawValue == "commandFinished")
        #expect(EventIdentifier.plugin("logViewer.lineAppended").rawValue == "logViewer.lineAppended")
    }

    @Test("pane metadata remains available after relocation to pane runtime contracts")
    func paneMetadataRelocation() {
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "X"), title: "X")
        #expect(metadata.title == "X")
        #expect(metadata.contentType == .terminal)
        #expect(metadata.executionBackend == .local)
        #expect(metadata.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("system source supports typed and plugin producers")
    func systemSourceExtensibility() {
        #expect(EventSource.system(.filesystemWatcher).description == "system:filesystemWatcher")
        #expect(EventSource.system(.gitForge).description == "system:gitForge")
        #expect(EventSource.system(.containerService).description == "system:containerService")
        #expect(EventSource.system(.plugin("forge.github")).description == "system:plugin:forge.github")
    }
}
