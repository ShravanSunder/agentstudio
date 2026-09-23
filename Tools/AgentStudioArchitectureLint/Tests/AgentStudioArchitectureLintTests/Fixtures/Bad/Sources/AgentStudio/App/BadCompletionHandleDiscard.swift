@MainActor
final class BadCompletionHandleExecutor {
    @discardableResult
    func submitCompletionHandleGesture(_ operation: @escaping @MainActor () async -> Bool) -> Task<Bool, Never> {
        Task { await operation() }
    }

    func submit(_ value: Int) -> Task<Bool, Never> {
        Task { value > 0 }
    }

    func dispatchCompletionHandleAction(owner: BadCompletionHandleExecutor?) {
        _ = submitCompletionHandleGesture { true }
        _ = submit(1)
        _ = owner?.submit(2)
    }

    func discardInsideWrappersWithoutReason(ready: Bool) {
        // fire-and-forget: separated from its discard by a blank line

        defer { _ = submit(7) }
        if ready { _ = submit(8) }
    }
}

final class BadCompletionHandleValidationExecutor {
    func submit(_ value: Int) -> Bool {
        value > 0
    }
}

actor BadCompletionHandleCaller {
    func dispatchAcrossActor(executor: BadCompletionHandleExecutor) async {
        _ = await executor.submit(3)
    }
}
