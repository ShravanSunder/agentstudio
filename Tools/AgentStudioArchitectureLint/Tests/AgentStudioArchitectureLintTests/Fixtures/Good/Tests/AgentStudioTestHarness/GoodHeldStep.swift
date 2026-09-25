import Foundation

final class GoodHeldStepGate: @unchecked Sendable {
    private var arrivals: [CheckedContinuation<Void, any Error>] = []
    private let parked = DispatchSemaphore(value: 0)

    func release() {
        parked.signal()
    }
}

func waitForArrival() async {}
