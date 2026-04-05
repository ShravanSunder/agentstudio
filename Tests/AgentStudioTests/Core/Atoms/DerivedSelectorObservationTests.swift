import Observation
import Testing

@testable import AgentStudio

private final class ObservationFlag: @unchecked Sendable {
    var fired = false
}

@MainActor
struct DerivedSelectorObservationTests {
    @Test
    func paneDisplayDerived_tracksUnderlyingAtomReads() async throws {
        withTestAtomStore { atoms in
            let pane = Pane(
                content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
                metadata: PaneMetadata(
                    source: .floating(launchDirectory: nil, title: nil),
                    title: "Initial"
                )
            )
            atoms.workspace.addPane(pane)

            let flag = ObservationFlag()
            let selector = PaneDisplayDerived()

            withObservationTracking {
                _ = selector.displayLabel(for: pane.id)
            } onChange: {
                flag.fired = true
            }

            atoms.workspace.renamePane(pane.id, title: "Updated")

            #expect(flag.fired)
        }
    }
}
