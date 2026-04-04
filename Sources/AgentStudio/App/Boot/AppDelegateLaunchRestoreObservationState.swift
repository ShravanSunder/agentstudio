import Foundation

@MainActor
final class AppDelegateLaunchRestoreObservationState {
    private(set) var didComplete = false
    private var diagnosticTask: Task<Void, Never>?

    func prepareForObservation() {
        didComplete = false
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }

    func installDiagnosticTask(_ task: Task<Void, Never>) {
        diagnosticTask?.cancel()
        diagnosticTask = task
    }

    func complete() {
        guard !didComplete else { return }
        didComplete = true
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }

    func cancelDiagnostics() {
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }
}
