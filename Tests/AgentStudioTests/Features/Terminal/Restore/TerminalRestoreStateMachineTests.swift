import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct TerminalRestoreStateMachineTests {
    @Test
    func stateMachine_requiresTrustedGeometry_beforeStartingSurface() async {
        let machine = Machine<TerminalRestoreState>(initialState: .init())

        await machine.send(.beginRestore)

        #expect(machine.state.phase == .waitingForTrustedGeometry)
    }

    @Test
    func stateMachine_exposesTruthfulRestoringState_forVisiblePaneInFlight() async {
        let machine = Machine<TerminalRestoreState>(
            initialState: .init(phase: .waitingForTrustedGeometry)
        )

        await machine.send(.geometryResolved(CGRect(x: 0, y: 0, width: 1200, height: 700)))
        await machine.send(.surfaceCreated)
        await machine.send(.promotedToVisible)

        #expect(machine.state.phase == .startingSurface)
        #expect(machine.state.visiblePresentation == .restoring)
    }

    @Test
    func stateMachine_recordsPlaceholderFailure_insteadOfShellFallback() async {
        let machine = Machine<TerminalRestoreState>(
            initialState: .init(phase: .startingSurface)
        )

        await machine.send(.attachFailed(.timeout))

        #expect(machine.state.phase == .failed(.attachFailed(.timeout)))
        #expect(machine.state.visiblePresentation == .placeholder)
    }
}
