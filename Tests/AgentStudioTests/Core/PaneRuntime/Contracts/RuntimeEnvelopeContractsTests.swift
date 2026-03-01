import Foundation
import Testing

@testable import AgentStudio

@Suite("RuntimeEnvelope contracts")
struct RuntimeEnvelopeContractsTests {
    @Test("topology events use SystemEnvelope")
    func topologyRequiresSystemEnvelope() {
        let event = SystemScopedEvent.topology(
            .repoDiscovered(
                repoPath: URL(fileURLWithPath: "/tmp/repo"),
                parentPath: URL(fileURLWithPath: "/tmp")
            )
        )
        let envelope = RuntimeEnvelope.system(SystemEnvelope.test(event: event))

        if case .system = envelope {
            #expect(Bool(true))
        } else {
            #expect(Bool(false))
        }
    }
}
