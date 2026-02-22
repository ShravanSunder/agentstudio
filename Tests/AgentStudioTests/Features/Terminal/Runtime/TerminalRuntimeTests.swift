import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalRuntime lifecycle")
struct TerminalRuntimeTests {
    @Test("handleCommand rejects when lifecycle not ready")
    func rejectWhenNotReady() async {
        let runtime = TerminalRuntime(
            paneId: UUID(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        let commandEnvelope = makeEnvelope(command: .activate, paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        #expect(result == .failure(.runtimeNotReady(lifecycle: .created)))
    }

    @Test("handleCommand succeeds after ready transition")
    func succeedsWhenReady() async {
        let runtime = TerminalRuntime(
            paneId: UUID(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        let commandEnvelope = makeEnvelope(command: .terminal(.clearScrollback), paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        switch result {
        case .success(let commandId):
            #expect(commandId == commandEnvelope.commandId)
        default:
            Issue.record("Expected success result for ready runtime")
        }
    }

    private func makeEnvelope(command: PaneCommand, paneId: UUID) -> PaneCommandEnvelope {
        let clock = ContinuousClock()
        return PaneCommandEnvelope(
            commandId: UUID(),
            correlationId: nil,
            targetPaneId: paneId,
            command: command,
            timestamp: clock.now
        )
    }
}
