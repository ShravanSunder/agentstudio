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
