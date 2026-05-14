import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct AppDelegateLaunchRestoreObservationStateTests {
    @Test("complete cancels diagnostics and marks restore complete")
    func complete_cancelsDiagnosticsAndMarksRestoreComplete() async {
        let state = AppDelegateLaunchRestoreObservationState()
        let diagnosticTask = makePendingDiagnosticTask()
        state.installDiagnosticTask(diagnosticTask)

        state.complete()

        #expect(state.didComplete == true)
        #expect(diagnosticTask.isCancelled == true)
    }

    @Test("cancelDiagnostics stops the timer without marking restore complete")
    func cancelDiagnostics_stopsTimerWithoutMarkingRestoreComplete() async {
        let state = AppDelegateLaunchRestoreObservationState()
        let diagnosticTask = makePendingDiagnosticTask()
        state.installDiagnosticTask(diagnosticTask)

        state.cancelDiagnostics()

        #expect(state.didComplete == false)
        #expect(diagnosticTask.isCancelled == true)
    }

    @Test("complete is idempotent")
    func complete_isIdempotent() async {
        let state = AppDelegateLaunchRestoreObservationState()
        state.complete()
        state.complete()

        #expect(state.didComplete == true)
    }

    private func makePendingDiagnosticTask() -> Task<Void, Never> {
        Task<Void, Never> { @MainActor in
            let stream = AsyncStream<Void> { _ in }
            for await _ in stream {}
        }
    }
}
