import Foundation

/// One cancellable deadline; an admitted validation/commit always finishes before shutdown returns.
package actor RepositoryRetentionScheduler {
    private let clock: GitRefreshDeadlineClock
    private let onDeadline: @Sendable () async -> Void
    private var sleeper: Task<Void, Never>?
    private var validation: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var pendingDeadline: Duration?
    private var isShuttingDown = false

    package init<SourceClock: Clock & Sendable>(clock: SourceClock, onDeadline: @escaping @Sendable () async -> Void)
    where SourceClock.Duration == Duration {
        self.clock = GitRefreshDeadlineClock(clock)
        self.onDeadline = onDeadline
    }

    package func schedule(after delay: Duration?) async {
        guard !isShuttingDown else { return }
        generation &+= 1
        let expectedGeneration = generation
        pendingDeadline = delay.map { clock.now + max(.zero, $0) }
        let previous = sleeper
        sleeper = nil
        previous?.cancel()
        await previous?.value
        guard generation == expectedGeneration, validation == nil else { return }
        armDeadline()
    }

    private func armDeadline() {
        guard !isShuttingDown, let deadline = pendingDeadline else { return }
        let expectedGeneration = generation
        let clock = self.clock
        sleeper = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.fire(expectedGeneration)
        }
    }

    private func fire(_ expectedGeneration: UInt64) {
        guard !isShuttingDown, generation == expectedGeneration, validation == nil else { return }
        sleeper = nil
        pendingDeadline = nil
        let onDeadline = self.onDeadline
        validation = Task { [weak self] in
            await onDeadline()
            await self?.finishValidation()
        }
    }

    private func finishValidation() {
        validation = nil
        armDeadline()
    }

    package func shutdown() async {
        isShuttingDown = true
        generation &+= 1
        pendingDeadline = nil
        let sleeper = self.sleeper
        self.sleeper = nil
        sleeper?.cancel()
        await sleeper?.value
        await validation?.value
    }
}
