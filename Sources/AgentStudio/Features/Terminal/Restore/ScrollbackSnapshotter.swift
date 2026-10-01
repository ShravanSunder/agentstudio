import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// One off-main cadence and one bounded fleet. Periodic and quit callers
/// share the fleet, including its queued targets, rather than opening a
/// second pool of captures. Retirement remains a per-pane write exclusion.
package actor ScrollbackSnapshotter {
    private struct FleetResult: Sendable {
        let outcome: ScrollbackPassOutcome
        let paneCount: Int
        var paneIDs: Set<PaneId> = []
    }

    private struct CaptureFleet {
        let id: UUID
        let owner: ScrollbackSnapshotterScope
        let task: Task<FleetResult, Never>
        var callers: Set<ScrollbackSnapshotterScope>
        var bindings: [ScrollbackPaneBinding]?
    }

    private struct CaptureAttempt {
        let id: UUID
        let task: Task<ScrollbackSnapshotDisposition, Never>
    }

    private enum QuitRaceResult: Sendable {
        case pass(ScrollbackPassOutcome)
        case deadline, cancelled
    }

    private let clock: ScrollbackSnapshotClock
    private let store: ScrollbackStore
    private let inventory: @Sendable () async -> ZmxSessionInventory
    private let paneBindings: @Sendable () async throws -> [ScrollbackPaneBinding]
    private let capture: @Sendable (ZmxSessionID) async -> ScrollbackCaptureResult
    private let captureInterval: Duration
    private let maximumConcurrentCaptures: Int
    private let factSink: (@Sendable (ScrollbackSnapshotterScope, ScrollbackSnapshotterFact) -> Void)?
    private var schedulerTask: Task<Void, Never>?
    private var fleet: CaptureFleet?
    private var attempts: [PaneId: CaptureAttempt] = [:]
    private var retiredPaneIDs: Set<PaneId> = []
    private var isQuitting = false
    private var isStopping = false
    private var didAnnounceStopped = false

    package init(
        clock: any Clock<Duration>, store: ScrollbackStore,
        inventory: @escaping @Sendable () async -> ZmxSessionInventory,
        paneBindings: @escaping @Sendable () async throws -> [ScrollbackPaneBinding],
        capture: @escaping @Sendable (ZmxSessionID) async -> ScrollbackCaptureResult,
        maximumConcurrentCaptures: Int = AppPolicies.Restore.maximumConcurrentCaptures,
        captureInterval: Duration = AppPolicies.Restore.captureInterval,
        delay: AsyncDelay? = nil,
        factSink: (@Sendable (ScrollbackSnapshotterScope, ScrollbackSnapshotterFact) -> Void)? = nil
    ) {
        precondition(maximumConcurrentCaptures > 0 && captureInterval > .zero)
        self.clock = ScrollbackSnapshotClock(clock, delay: delay)
        self.store = store
        self.inventory = inventory
        self.paneBindings = paneBindings
        self.capture = capture
        self.maximumConcurrentCaptures = maximumConcurrentCaptures
        self.captureInterval = captureInterval
        self.factSink = factSink
    }

    package func announceFirstFrameWait() {
        emit(.scheduler, .firstFrameGateWaiting)
    }

    package func startAfterFirstFrame() {
        emit(.scheduler, .firstFrameGatePassed)
        start()
    }

    package func start() {
        guard schedulerTask == nil, !isQuitting, !isStopping else { return }
        let clock = clock
        let interval = captureInterval
        let firstDeadline = clock.now + interval
        emit(.scheduler, .scheduled)
        schedulerTask = Task { [weak self] in
            var deadline = firstDeadline
            while !Task.isCancelled {
                do { try await clock.sleep(until: deadline) } catch { return }
                guard !Task.isCancelled, let self else { return }
                await self.runPeriodicPass()
                guard !Task.isCancelled else { return }
                deadline = clock.now + interval
            }
        }
    }

    private func runPeriodicPass() async {
        guard !isQuitting, !isStopping else { return }
        _ = await runPass(scope: .pass(UUIDv7.generate()), reason: .periodic)
    }

    package func captureForQuit(requestID: UUID, budget: Duration) async -> ScrollbackQuitOutcome {
        emit(.quit(requestID), .quitStarted)
        isQuitting = true
        schedulerTask?.cancel()
        let deadline = clock.now + max(.zero, budget)
        let clock = clock
        let outcome = await withTaskGroup(of: QuitRaceResult.self, returning: ScrollbackQuitOutcome.self) { group in
            group.addTask { [self] in
                let pass = await runPass(scope: .pass(requestID), reason: .quit)
                return .pass(pass.outcome)
            }
            group.addTask {
                do { try await clock.sleep(until: deadline) } catch { return .cancelled }
                return .deadline
            }
            let first = await group.next() ?? .cancelled
            let outcome: ScrollbackQuitOutcome
            switch first {
            case .pass(let passOutcome):
                outcome = Task.isCancelled || passOutcome == .cancelled ? .cancelled : .completed
            case .deadline:
                outcome = .deadlineExceeded
                cancelFleet()
            case .cancelled:
                outcome = .cancelled
                cancelFleet()
            }
            group.cancelAll()
            // Cancellation never detaches an inventory probe, capture or
            // prepared file write from its owning pass.
            for await _ in group {}
            return outcome
        }
        emit(.quit(requestID), .quitFinished(outcome))
        return outcome
    }

    private func runPass(scope: ScrollbackSnapshotterScope, reason: ScrollbackPassReason) async -> FleetResult {
        emit(scope, .passStarted(reason))
        guard !isStopping, !Task.isCancelled else {
            let result = FleetResult(outcome: .cancelled, paneCount: 0)
            emit(scope, .passFinished(outcome: result.outcome, capturedPaneCount: result.paneCount))
            return result
        }
        let joinedActiveFleet = fleet != nil
        let task = acquireFleet(scope: scope)
        var result = await task.value
        if reason == .quit, joinedActiveFleet, result.outcome == .completed, !Task.isCancelled, !isStopping {
            // A shared periodic inventory may predate a pane created while
            // its capture was running. Read fresh bindings for quit and
            // capture only those not already visited by the shared fleet.
            let additional = await acquireFleet(scope: scope, excluding: result.paneIDs).value
            let paneIDs = result.paneIDs.union(additional.paneIDs)
            result = .init(outcome: additional.outcome, paneCount: paneIDs.count, paneIDs: paneIDs)
        }
        emit(scope, .passFinished(outcome: result.outcome, capturedPaneCount: result.paneCount))
        return result
    }

    private func acquireFleet(
        scope: ScrollbackSnapshotterScope, excluding paneIDs: Set<PaneId> = []
    ) -> Task<FleetResult, Never> {
        let task: Task<FleetResult, Never>
        if var current = fleet {
            current.callers.insert(scope)
            if let bindings = current.bindings {
                for binding in bindings { emit(scope, .captureJoined(binding)) }
            }
            fleet = current
            task = current.task
        } else {
            let id = UUIDv7.generate()
            task = Task { [self] in await captureFleet(id: id, excluding: paneIDs) }
            fleet = CaptureFleet(id: id, owner: scope, task: task, callers: [scope], bindings: nil)
        }
        return task
    }

    private func captureFleet(id: UUID, excluding paneIDs: Set<PaneId>) async -> FleetResult {
        defer { if fleet?.id == id { fleet = nil } }
        let inventory = await inventory()
        guard !Task.isCancelled else { return .init(outcome: .cancelled, paneCount: 0) }
        guard case .complete(let entries) = inventory else {
            return .init(outcome: .inventoryUnavailable, paneCount: 0)
        }
        let bindings: [ScrollbackPaneBinding]
        do { bindings = try await paneBindings() } catch {
            return .init(outcome: Task.isCancelled ? .cancelled : .bindingsUnavailable, paneCount: 0)
        }
        var seenPaneIDs: Set<PaneId> = []
        let targets = bindings.filter { binding in
            guard case .alive? = entries[binding.sessionID], !retiredPaneIDs.contains(binding.paneID),
                !paneIDs.contains(binding.paneID)
            else { return false }
            return seenPaneIDs.insert(binding.paneID).inserted
        }
        guard !Task.isCancelled, var current = fleet, current.id == id else {
            return .init(outcome: .cancelled, paneCount: 0)
        }
        current.bindings = targets
        fleet = current
        for caller in current.callers {
            for binding in targets {
                emit(caller, caller == current.owner ? .captureAdmitted(binding) : .captureJoined(binding))
            }
        }
        await withTaskGroup(of: Void.self) { group in
            var remaining = targets.makeIterator()
            for _ in 0..<maximumConcurrentCaptures {
                guard let binding = remaining.next() else { break }
                group.addTask { [self] in await captureTarget(binding) }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, let binding = remaining.next() else { continue }
                group.addTask { [self] in await captureTarget(binding) }
            }
        }
        return .init(
            outcome: Task.isCancelled ? .cancelled : .completed, paneCount: targets.count,
            paneIDs: Set(targets.map(\.paneID)))
    }

    private func captureTarget(_ binding: ScrollbackPaneBinding) async {
        guard !Task.isCancelled else { return }
        let id = UUIDv7.generate()
        let task = Task { [self] in await captureAndStore(binding, attemptID: id) }
        attempts[binding.paneID] = .init(id: id, task: task)
        _ = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if attempts[binding.paneID]?.id == id { attempts.removeValue(forKey: binding.paneID) }
    }

    private func captureAndStore(_ binding: ScrollbackPaneBinding, attemptID: UUID) async
        -> ScrollbackSnapshotDisposition
    {
        let scope = ScrollbackSnapshotterScope.capture(paneID: binding.paneID, attemptID: attemptID)
        emit(scope, .captureStarted(binding))
        let disposition: ScrollbackSnapshotDisposition
        if retiredPaneIDs.contains(binding.paneID) {
            disposition = .retired
        } else if Task.isCancelled || isStopping {
            disposition = .cancelled
        } else {
            let result = await capture(binding.sessionID)
            if retiredPaneIDs.contains(binding.paneID) {
                disposition = .retired
            } else if Task.isCancelled || isStopping {
                disposition = .cancelled
            } else {
                disposition = await persist(result, for: binding.paneID)
            }
        }
        emit(scope, .captureFinished(disposition))
        return disposition
    }

    private func persist(_ result: ScrollbackCaptureResult, for paneID: PaneId) async -> ScrollbackSnapshotDisposition {
        switch result {
        case .accepted(let data):
            do {
                switch try await store.store(paneId: paneID, capture: data) {
                case .written: return .written
                case .unchanged: return .unchanged
                case .retired: return .retired
                }
            } catch {
                if retiredPaneIDs.contains(paneID) { return .retired }
                return Task.isCancelled ? .cancelled : .writeFailed
            }
        case .empty: return .empty
        case .deadlineExceeded: return .deadlineExceeded
        case .exceededCeiling: return .exceededCeiling
        case .launchFailed(let errno): return .launchFailed(errno: errno)
        case .readFailed: return .readFailed
        case .exitedNonZero(let status): return .exitedNonZero(status)
        }
    }

    /// Thin App forward passes UUIDs unchanged; conversion stays off-main.
    package func retire(operationID: UUID, paneUUIDs: Set<UUID>) async throws {
        try await retire(operationID: operationID, paneIDs: Set(paneUUIDs.map { PaneId(existingUUID: $0) }))
    }

    package func retire(operationID: UUID, paneIDs: Set<PaneId>) async throws {
        retiredPaneIDs.formUnion(paneIDs)
        emit(.retirement(operationID), .retirementStarted(paneIDs))
        var deletionError: (any Error)?
        do { try await store.retire(paneIds: paneIDs) } catch { deletionError = error }
        let retiring = paneIDs.compactMap { attempts[$0]?.task }
        for task in retiring { task.cancel() }
        for task in retiring { _ = await task.value }
        emit(.retirement(operationID), .retirementFinished)
        if let deletionError { throw deletionError }
    }

    private func cancelFleet() {
        fleet?.task.cancel()
        for attempt in attempts.values { attempt.task.cancel() }
    }

    package func shutdown() async {
        isStopping = true
        let scheduler = schedulerTask
        let activeFleet = fleet?.task
        let activeAttempts = attempts.values.map(\.task)
        scheduler?.cancel()
        cancelFleet()
        for attempt in activeAttempts { _ = await attempt.value }
        _ = await activeFleet?.value
        await scheduler?.value
        schedulerTask = nil
        if !didAnnounceStopped {
            didAnnounceStopped = true
            emit(.scheduler, .stopped)
        }
    }

    private func emit(_ scope: ScrollbackSnapshotterScope, _ fact: ScrollbackSnapshotterFact) {
        factSink?(scope, fact)
    }
}

/// Durations from an origin preserve absolute deadlines with an existential
/// production or test clock, without erasing its cancellation semantics.
private struct ScrollbackSnapshotClock: Sendable {
    private let nowValue: @Sendable () -> Duration
    private let sleepValue: @Sendable (Duration) async throws -> Void

    init<SourceClock: Clock>(_ clock: SourceClock, delay: AsyncDelay?) where SourceClock.Duration == Duration {
        let origin = clock.now
        nowValue = { origin.duration(to: clock.now) }
        sleepValue = { deadline in
            if let delay {
                // Production uses the existing nanosecond sleep seam to
                // avoid the macOS generic-clock deallocation crash. The
                // monotonic clock still owns the absolute deadline.
                try await delay.wait(max(.zero, deadline - origin.duration(to: clock.now)))
            } else {
                try await clock.sleep(until: origin.advanced(by: deadline), tolerance: nil)
            }
        }
    }

    var now: Duration { nowValue() }
    func sleep(until deadline: Duration) async throws { try await sleepValue(deadline) }
}
