import Dispatch
import Foundation

struct BadBlockingCooperativeWaitTest {
    func readsSocketOnTheCooperativeThread(connection: FakeSocketConnection) throws {
        _ = try connection.receive(maxBytes: 4096)
    }

    func waitsOnANamedSemaphore() {
        let release = DispatchSemaphore(value: 0)
        release.wait()
    }

    func waitsOnAFreshlyConstructedSemaphore() {
        _ = DispatchSemaphore(value: 0).wait(timeout: .now() + 1)
    }
}

struct FakeSocketConnection {
    func receive(maxBytes: Int) throws -> Data {
        _ = maxBytes
        return Data()
    }
}
