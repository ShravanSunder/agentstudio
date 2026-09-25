import Dispatch
import Foundation

struct BadDedicatedThreadBlockingWaitTest {
    func waitsOnASemaphoreOnTheCooperativeThread() async {
        let release = DispatchSemaphore(value: 0)
        release.signal()
        release.wait()
        await valueFromDedicatedThread {}
    }
}

func valueFromDedicatedThread<Value: Sendable>(
    _ blockingWork: @escaping @Sendable () -> Value
) async -> Value {
    blockingWork()
}
