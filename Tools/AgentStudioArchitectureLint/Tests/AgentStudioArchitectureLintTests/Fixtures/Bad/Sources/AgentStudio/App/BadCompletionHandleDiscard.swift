@MainActor
final class BadCompletionHandleExecutor {
    @discardableResult
    func submitCompletionHandleGesture(_ operation: @escaping @MainActor () async -> Bool) -> Task<Bool, Never> {
        Task { await operation() }
    }

    func dispatchCompletionHandleAction() {
        _ = submitCompletionHandleGesture { true }
    }
}
