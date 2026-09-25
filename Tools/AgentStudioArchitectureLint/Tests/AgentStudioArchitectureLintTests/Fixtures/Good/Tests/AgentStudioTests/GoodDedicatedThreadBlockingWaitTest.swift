import Dispatch
import Foundation

struct GoodDedicatedThreadBlockingWaitTest {
    func waitsOnASemaphoreFromADedicatedThread() async {
        let release = DispatchSemaphore(value: 0)
        release.signal()
        await valueFromDedicatedThread { release.wait() }
    }
}

func valueFromDedicatedThread<Value: Sendable>(
    _ blockingWork: @escaping @Sendable () -> Value
) async -> Value {
    blockingWork()
}
