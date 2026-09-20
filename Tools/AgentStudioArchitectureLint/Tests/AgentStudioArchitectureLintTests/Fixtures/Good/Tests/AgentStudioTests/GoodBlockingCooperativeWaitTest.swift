import Dispatch
import Foundation

struct GoodBlockingCooperativeWaitTest {
    private let waitMention = "connection.receive(maxBytes: 4096)"

    func commentAndStringMentionsAreAllowed() {
        // connection.receive(maxBytes: 4096) is policy text here, not a call.
        _ = waitMention
    }

    func readsSocketOffTheCooperativePool(connection: FakeSocketConnection) async throws {
        _ = try await withoutBlockingCooperativePool { try connection.receive(maxBytes: 4096) }
    }

    func waitsForAnEventInstead(harness: FakeEventHarness) async {
        await harness.waitForNextEvent()
    }
}

struct FakeSocketConnection: Sendable {
    func receive(maxBytes: Int) throws -> Data {
        _ = maxBytes
        return Data()
    }
}

struct FakeEventHarness {
    func waitForNextEvent() async {}
}

func withoutBlockingCooperativePool<Value: Sendable>(
    _ blockingWork: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try blockingWork()
}
