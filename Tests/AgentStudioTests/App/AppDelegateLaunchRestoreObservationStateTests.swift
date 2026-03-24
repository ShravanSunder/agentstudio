import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct AppDelegateLaunchRestoreObservationStateTests {
    @Test("complete cancels diagnostics and marks restore complete")
    func complete_cancelsDiagnosticsAndMarksRestoreComplete() async {
        let state = AppDelegateLaunchRestoreObservationState()
        let diagnosticTask = Task<Void, Never> { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            return ()
        }
        state.installDiagnosticTask(diagnosticTask)

        state.complete()

        #expect(state.didComplete == true)
        #expect(diagnosticTask.isCancelled == true)
    }

    @Test("cancelDiagnostics stops the timer without marking restore complete")
    func cancelDiagnostics_stopsTimerWithoutMarkingRestoreComplete() async {
        let state = AppDelegateLaunchRestoreObservationState()
        let diagnosticTask = Task<Void, Never> { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            return ()
        }
        state.installDiagnosticTask(diagnosticTask)

        state.cancelDiagnostics()

        #expect(state.didComplete == false)
        #expect(diagnosticTask.isCancelled == true)
    }
}
