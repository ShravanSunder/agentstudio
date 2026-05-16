import Foundation

@testable import AgentStudio

actor CommandDispatcherTestIsolation {
    static let shared = CommandDispatcherTestIsolation()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        precondition(isLocked)
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        waiters.removeFirst().resume()
    }
}

@MainActor
func withIsolatedCommandDispatcher<T>(
    configure: @MainActor () -> Void,
    body: @MainActor () async throws -> T
) async throws -> T {
    await CommandDispatcherTestIsolation.shared.acquire()
    let previousHandler = CommandDispatcher.shared.handler
    let previousRouter = CommandDispatcher.shared.appCommandRouter
    configure()

    do {
        let result = try await body()
        CommandDispatcher.shared.handler = previousHandler
        CommandDispatcher.shared.appCommandRouter = previousRouter
        await CommandDispatcherTestIsolation.shared.release()
        return result
    } catch {
        CommandDispatcher.shared.handler = previousHandler
        CommandDispatcher.shared.appCommandRouter = previousRouter
        await CommandDispatcherTestIsolation.shared.release()
        throw error
    }
}
