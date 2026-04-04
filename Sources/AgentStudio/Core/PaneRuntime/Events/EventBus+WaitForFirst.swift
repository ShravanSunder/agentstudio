import Foundation

extension EventBus {
    /// Subscribes and waits for the first envelope matching the extract closure.
    ///
    /// Returns as soon as a match is found. If the stream ends without a match
    /// (e.g. the bus is deallocated or the task is cancelled), returns nil.
    ///
    /// Cleanup is automatic — the subscription is removed when this method returns.
    ///
    /// - Parameter extract: Tests each envelope and returns an extracted value
    ///   on match, or nil to continue waiting.
    /// - Returns: The extracted result, or nil if the stream ended without matching.
    func waitForFirst<Result: Sendable>(
        _ extract: @Sendable @escaping (Envelope) -> Result?
    ) async -> Result? {
        let stream = await subscribe()
        for await envelope in stream {
            if let result = extract(envelope) {
                return result
            }
        }
        return nil
    }

    /// Subscribes and waits for the first matching envelope, with a time limit.
    ///
    /// Uses a TaskGroup race between the envelope consumer and a sleep task.
    /// Returns nil if the timeout expires before a match, even if no events arrive.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait for a matching event.
    ///   - clock: Clock for timeout measurement. Inject a test clock for
    ///     deterministic testing. Defaults to `ContinuousClock()`.
    ///   - extract: Tests each envelope and returns an extracted value
    ///     on match, or nil to continue waiting.
    /// - Returns: The extracted result, or nil if the timeout expired or stream ended.
    func waitForFirst<Result: Sendable>(
        timeout: Duration,
        clock: some Clock<Duration> = ContinuousClock(),
        _ extract: @Sendable @escaping (Envelope) -> Result?
    ) async -> Result? {
        await withTaskGroup(of: Result?.self) { group in
            group.addTask {
                let stream = await self.subscribe()
                for await envelope in stream {
                    if let result = extract(envelope) {
                        return result
                    }
                }
                return nil
            }

            group.addTask {
                try? await clock.sleep(for: timeout)
                return nil
            }

            while let result = await group.next() {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }

            return nil
        }
    }
}
