import Foundation

enum RestoreResumeReadinessResult: Equatable, Sendable { case ready, unavailable }

enum RestoreResumeReadinessFact: Equatable, Sendable {
    case listenerReady
    case boundaryRead(LifecycleReportBoundary)
    case launchPrepared
    case reportsTakenIn(LifecycleReportBoundary)
    case published(RestoreResumeReadinessResult)
    case waiting
    case decided(RestoreResumeReadinessResult)
}

/// Owns the launch deadline and one immutable readiness decision off MainActor.
actor RestoreResumeReadiness<ReadinessClock: Clock> where ReadinessClock.Duration == Duration {
    private let clock: ReadinessClock
    private let deadlineDelay: Duration
    private let launchId: UUID
    private let factSink: @Sendable (UUID, RestoreResumeReadinessFact) -> Void
    private var result: RestoreResumeReadinessResult?
    private var decisions: [UUID: RestoreResumeReadinessResult] = [:]
    private var waiters: [UUID: [AsyncStream<RestoreResumeReadinessResult>.Continuation]] = [:]
    private var deadlineTask: Task<Void, Never>?

    init(
        clock: ReadinessClock, deadline: Duration, launchId: UUID,
        factSink: @escaping @Sendable (UUID, RestoreResumeReadinessFact) -> Void
    ) {
        self.clock = clock
        deadlineDelay = deadline
        self.launchId = launchId
        self.factSink = factSink
    }

    func record(_ fact: RestoreResumeReadinessFact) {
        guard result == nil else { return }
        armDeadlineIfNeeded()
        factSink(launchId, fact)
    }

    func publish(_ value: RestoreResumeReadinessResult) {
        guard result == nil else { return }
        result = value
        deadlineTask?.cancel()
        factSink(launchId, .published(value))
        let pending = waiters
        waiters.removeAll()
        for (paneId, continuations) in pending {
            decisions[paneId] = value
            factSink(paneId, .decided(value))
            for continuation in continuations {
                continuation.yield(value)
                continuation.finish()
            }
        }
    }

    func wait(paneId: UUID) async -> RestoreResumeReadinessResult {
        if let decided = decisions[paneId] { return decided }
        if waiters[paneId] == nil { factSink(paneId, .waiting) }
        if let result {
            decisions[paneId] = result
            factSink(paneId, .decided(result))
            return result
        }
        armDeadlineIfNeeded()
        let (stream, continuation) = AsyncStream.makeStream(
            of: RestoreResumeReadinessResult.self, bufferingPolicy: .bufferingNewest(1))
        waiters[paneId, default: []].append(continuation)
        for await value in stream { return value }
        return .unavailable
    }

    private func armDeadlineIfNeeded() {
        guard deadlineTask == nil, result == nil else { return }
        let clock = clock
        let deadline = clock.now.advanced(by: deadlineDelay)
        deadlineTask = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
                await self?.publish(.unavailable)
            } catch {}
        }
    }

    func shutdown() async {
        publish(.unavailable)
        deadlineTask?.cancel()
        await deadlineTask?.value
        deadlineTask = nil
    }
}

extension AppIPCDeferredInitialization {
    @concurrent nonisolated static func prepareResumeReadiness<ReadinessClock: Clock>(
        readiness: RestoreResumeReadiness<ReadinessClock>,
        intake: any LifecycleReportIntaking,
        prepareForLaunch: @escaping @Sendable () async throws -> Void
    ) async where ReadinessClock.Duration == Duration {
        await readiness.record(.listenerReady)
        let boundary: LifecycleReportBoundary
        do {
            boundary = try await intake.captureListenerReadyBoundary()
        } catch {
            // Store unavailability must not skip the existing launch sweep.
            _ = try? await prepareForLaunch()
            await readiness.publish(.unavailable)
            return
        }
        do {
            await readiness.record(.boundaryRead(boundary))
            try await prepareForLaunch()
            await readiness.record(.launchPrepared)
            try await intake.takeIn(through: boundary)
            await readiness.record(.reportsTakenIn(boundary))
            await readiness.publish(.ready)
        } catch {
            await readiness.publish(.unavailable)
        }
    }
}
