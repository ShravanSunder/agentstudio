@MainActor
final class GoodCompletionHandleExecutor {
    private var pendingGesture: Task<Bool, Never>?

    func submit(_ value: Int) -> Task<Bool, Never> {
        Task { value > 0 }
    }

    func submitCompletionHandleGesture(_ operation: @escaping @MainActor () async -> Bool) -> Task<Bool, Never> {
        Task { await operation() }
    }

    func awaitOutcome() async -> Bool {
        _ = await submitCompletionHandleGesture { true }.value
        return await submitCompletionHandleGesture { false }.value
    }

    func storeHandle() {
        pendingGesture = submitCompletionHandleGesture { true }
    }

    func discardWithReason(owner: GoodCompletionHandleExecutor?) {
        _ = submitCompletionHandleGesture { true }  // fire-and-forget: gesture handler, no caller
        _ = owner?.submitCompletionHandleGesture { true }  // fire-and-forget: owner drains its tail
        // fire-and-forget: menu action; the executor serializes and logs the outcome
        _ = self.submitCompletionHandleGesture { true }
    }
}

/// A second `submit` with a non-task result makes the name ambiguous for the
/// syntax-only index; the compiler still rejects a bare discard of either one.
final class GoodCompletionHandleValidationExecutor {
    func submit(_ value: Int) -> Bool {
        value > 0
    }

    func discardAmbiguousName(executor: GoodCompletionHandleExecutor) {
        _ = submit(1)
        _ = executor.submit(1)
    }
}
