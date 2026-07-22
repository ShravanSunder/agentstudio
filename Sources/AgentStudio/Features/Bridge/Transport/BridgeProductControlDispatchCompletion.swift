actor BridgeProductControlDispatchCompletion {
    private var isCompleted = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if isCompleted { return }
        await withCheckedContinuation { continuation in
            precondition(waiter == nil)
            waiter = continuation
        }
    }

    func complete() {
        guard !isCompleted else { return }
        isCompleted = true
        waiter?.resume()
        waiter = nil
    }
}
