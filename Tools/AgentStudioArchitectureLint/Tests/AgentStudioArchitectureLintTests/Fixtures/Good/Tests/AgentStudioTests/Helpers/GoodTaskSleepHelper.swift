import Foundation

struct GoodTaskSleepHelper {
    func waitForState(using waiter: StateWaiter) async -> Bool {
        await waiter.waitForReadyState()
    }
}

struct StateWaiter {
    func waitForReadyState() async -> Bool { true }
}
