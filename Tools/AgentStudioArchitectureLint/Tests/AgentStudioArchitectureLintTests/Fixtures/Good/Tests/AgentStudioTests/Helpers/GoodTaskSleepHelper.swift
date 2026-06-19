import Foundation

struct GoodTaskSleepHelper {
    func waitForState(using waiter: StateWaiter) async {
        await waiter.waitForReadyState()
    }
}

struct StateWaiter {
    func waitForReadyState() async {}
}
