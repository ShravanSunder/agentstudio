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
        pendingGesture = submit(1)
    }

    func discardWithReason(owner: GoodCompletionHandleExecutor?) {
        _ = submit(1)  // fire-and-forget: gesture handler, no caller
        _ = owner?.submit(2)  // fire-and-forget: owner drains its tail
        // fire-and-forget: menu action; the executor serializes and logs the outcome
        _ = self.submitCompletionHandleGesture { true }
    }
}

final class GoodCompletionHandleValidationExecutor {
    func admitValidationRequest(_ value: Int) -> Bool {
        value > 0
    }
}

actor GoodCompletionHandleCaller {
    func dispatchAcrossActor(executor: GoodCompletionHandleExecutor) async -> Bool {
        _ = await executor.submit(3).value
        return await executor.submit(4).value
    }
}
