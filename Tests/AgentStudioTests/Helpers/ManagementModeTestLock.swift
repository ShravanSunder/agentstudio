import Foundation

@testable import AgentStudio

actor ManagementModeTestLock {
    static let shared = ManagementModeTestLock()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(
        _ body: @escaping @MainActor @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
            return
        }

        let nextWaiter = waiters.removeFirst()
        nextWaiter.resume()
    }
}

func withManagementModeTestLock<T: Sendable>(
    _ body: @escaping @MainActor @Sendable () async throws -> T
) async rethrows -> T {
    try await ManagementModeTestLock.shared.withLock(body)
}
