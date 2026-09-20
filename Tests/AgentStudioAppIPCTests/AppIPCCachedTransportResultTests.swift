import AgentStudioIPCTransport
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioAppIPC

@Suite("App IPC cached transport result")
struct AppIPCCachedTransportResultTests {
    @Test("the response is composed once however many times it is served")
    func composesOnce() throws {
        let compositionCount = LockedCounter()
        let cache = AppIPCCachedTransportResult {
            compositionCount.increment()
            return .object(["methods": .array([])])
        }

        let first = try cache.value()
        let second = try cache.value()
        let third = try cache.value()

        #expect(compositionCount.value == 1)
        #expect(first == second)
        #expect(second == third)
    }

    @Test("a failing composition is not cached and is retried")
    func failedCompositionIsNotCached() throws {
        let compositionCount = LockedCounter()
        let cache = AppIPCCachedTransportResult {
            compositionCount.increment()
            guard compositionCount.value > 1 else { throw CachedTransportProbeFailure() }
            return .object([:])
        }

        #expect(throws: CachedTransportProbeFailure.self) { try cache.value() }
        #expect(!cache.hasComposedValue)
        #expect(try cache.value() == .object([:]))
        #expect(cache.hasComposedValue)
    }

    @Test("concurrent first requests settle on one stored response")
    func concurrentFirstRequestsShareOneResponse() async throws {
        let cache = AppIPCCachedTransportResult { .object(["n": .number(1)]) }

        let values = try await withThrowingTaskGroup(of: JSONValue.self) { group in
            for _ in 0..<8 { group.addTask { try cache.value() } }
            var collected: [JSONValue] = []
            for try await value in group { collected.append(value) }
            return collected
        }

        #expect(values.count == 8)
        #expect(values.allSatisfy { $0 == .object(["n": .number(1)]) })
    }
}

private struct CachedTransportProbeFailure: Error {}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}
