import Foundation

@MainActor
final class AppDelegateLaunchRestoreObservationState {
    private(set) var didComplete = false
    private(set) var isInProgress = false
    private var diagnosticTask: Task<Void, Never>?

    func prepareForObservation() {
        didComplete = false
        isInProgress = false
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }

    func installDiagnosticTask(_ task: Task<Void, Never>) {
        diagnosticTask?.cancel()
        diagnosticTask = task
    }

    func beginRestoreIfNeeded() -> Bool {
        guard !didComplete, !isInProgress else { return false }
        isInProgress = true
        return true
    }

    func complete() {
        guard !didComplete else { return }
        didComplete = true
        isInProgress = false
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }

    func cancelDiagnostics() {
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }
}
