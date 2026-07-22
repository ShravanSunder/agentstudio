extension BridgeWorktreeProductConstructionCoordinator {
    func shutdown() async {
        if !isClosed {
            beginShutdown()
        }
        guard !entriesByNonce.isEmpty else { return }
        await withCheckedContinuation { continuation in
            if entriesByNonce.isEmpty {
                continuation.resume()
            } else {
                shutdownWaiters.append(continuation)
            }
        }
    }

    func ensureOpen() throws {
        guard !isClosed else {
            throw BridgeWorktreeProductConstructionError.coordinatorClosed
        }
    }
}
