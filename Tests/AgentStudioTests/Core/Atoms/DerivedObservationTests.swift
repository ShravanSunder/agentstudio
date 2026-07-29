import AgentStudioTestSupport
import Observation
import Testing

@testable import AgentStudioCore

private final class ObservationFlag: @unchecked Sendable {
    var fired = false
}

@MainActor
struct DerivedObservationTests {
    @Test
    func paneDisplayDerived_tracksUnderlyingAtomReads() async throws {
        withTestCoreAtoms { atoms in
            let pane = Pane(
                content: .terminal(
                    TerminalState(
                        provider: .zmx,
                        lifetime: .persistent,
                        zmxSessionID: .generateUUIDv7()
                    )
                ),
                metadata: PaneMetadata(
                    title: "Initial"
                )
            )
            atoms.workspacePane.addPane(pane)

            let flag = ObservationFlag()
            let selector = PaneDisplayDerived()

            withObservationTracking {
                _ = selector.displayLabel(for: pane.id)
            } onChange: {
                flag.fired = true
            }

            atoms.workspacePane.renamePane(pane.id, title: "Updated")

            #expect(flag.fired)
        }
    }
}
