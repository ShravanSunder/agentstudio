import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// Latest-state demand and future deadlines live here, off MainActor. A look
/// never absorbs a later trigger, and exit facts can only request fresh looks.
package actor PaneForegroundObserver<ObserverClock: Clock> where ObserverClock.Duration == Duration {
    private struct Demand {
        var dueAt: ObserverClock.Instant
        let maxAt: ObserverClock.Instant
        var requiredIdentity: Data?
        var quitting: Bool
    }
    private struct RunningLook {
        let scope: ForegroundObserverFactScope
        let sequence: UInt64
        let taskId: UUID
        let requiredIdentity: Data?
        let quitting: Bool
    }
    private struct OwnedWatch {
        let value: CurrentExitWatch
        let identity: Data
        let cancel: @Sendable () -> Void
        let listenerId: UUID
    }
    private struct PaneState {
        var outputActive: UUID?
        var pending: Demand?
        var followUp: Demand?
        var running: RunningLook?
        var watch: OwnedWatch?
        var quitDeadline: ObserverClock.Instant?
        var settled = false
    }
    private let clock: ObserverClock
    private let policy: ForegroundObserverPolicy
    private let repository: any PaneForegroundObservationRepository
    private let probe: any TerminalForegroundProbing
    private let exitWatcher: any ProcessExitWatching
    private let observerLaunchId: UUID
    private let factSink: ForegroundObserverFactSink
    private var panes: [UUID: PaneState] = [:]
    private var retiredPanes: Set<UUID> = []
    private var handoffs: Set<UUID> = []
    private var sequence: UInt64 = 0
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var deadlineTaskId: UUID?
    private var stopped = false

    package init(
        clock: ObserverClock,
        policy: ForegroundObserverPolicy,
        repository: any PaneForegroundObservationRepository,
        probe: any TerminalForegroundProbing,
        exitWatcher: any ProcessExitWatching,
        observerLaunchId: UUID,
        factSink: @escaping ForegroundObserverFactSink
    ) {
        self.clock = clock
        self.policy = policy
        self.repository = repository
        self.probe = probe
        self.exitWatcher = exitWatcher
        self.observerLaunchId = observerLaunchId
        self.factSink = factSink
    }

    package func note(_ trigger: ForegroundLookTrigger, pane: UUID) {
        guard !stopped, !retiredPanes.contains(pane), panes[pane]?.settled != true else { return }
        var state = panes[pane] ?? PaneState()
        let now = clock.now
        let due: ObserverClock.Instant
        switch trigger {
        case .outputBegan(let identifier):
            state.outputActive = identifier
            due = now.advanced(by: policy.lookMaxDelay)
        case .outputSettled(let identifier):
            guard state.outputActive == identifier else { return }
            state.outputActive = nil
            due = now.advanced(by: policy.lookSettleDelay)
        case .agentMessage: due = now.advanced(by: policy.lookSettleDelay)
        case .appQuitting:
            state.quitDeadline = now.advanced(by: policy.quitLookDeadline)
            due = now
        case .bindingChanged, .relaunched: due = now
        }
        let quitting = state.quitDeadline != nil
        mergeDemand(into: &state, due: due, identity: nil, quitting: quitting)
        panes[pane] = state
        let scope = newScope(pane)
        factSink(scope, .scheduled)
        factSink(scope, .closed(.scheduled))
        rescheduleDeadline()
    }

    private func mergeDemand(
        into state: inout PaneState, due: ObserverClock.Instant, identity: Data?, quitting: Bool
    ) {
        var demand = state.running == nil ? state.pending : state.followUp
        if var existing = demand {
            // Immediate triggers pull forward; settle triggers debounce within
            // the max fixed when this demand was first armed.
            existing.dueAt = due <= clock.now ? due : min(due, existing.maxAt)
            existing.requiredIdentity = identity
            existing.quitting = existing.quitting || quitting
            demand = existing
        } else {
            demand = Demand(
                dueAt: due, maxAt: clock.now.advanced(by: policy.lookMaxDelay),
                requiredIdentity: identity, quitting: quitting)
        }
        if state.running == nil { state.pending = demand } else { state.followUp = demand }
    }

    /// One sleep covers all pending looks and quit deadlines. Old sleeper ids
    /// are invalidated before cancellation, so a delivered wake stays inert.
    private func rescheduleDeadline() {
        if let old = deadlineTaskId { tasks[old]?.cancel() }
        deadlineTaskId = nil
        guard !stopped else { return }
        let deadline = panes.values.filter { !$0.settled }.flatMap { state in
            [state.pending?.dueAt, state.quitDeadline].compactMap { $0 }
        }.min()
        guard let deadline else { return }
        let identifier = UUIDv7.generate()
        deadlineTaskId = identifier
        let clock = clock
        tasks[identifier] = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
                await self?.deadlineReached(identifier)
            } catch {}
            await self?.taskFinished(identifier)
        }
    }

    private func deadlineReached(_ identifier: UUID) {
        guard deadlineTaskId == identifier, !stopped else { return }
        deadlineTaskId = nil
        let now = clock.now
        for pane in Array(panes.keys) {
            if let deadline = panes[pane]?.quitDeadline, deadline <= now { settleQuitDeadline(pane) }
        }
        var looks: [UUID: RunningLook] = [:]
        let taskId = UUIDv7.generate()
        for pane in Array(panes.keys) {
            guard var state = panes[pane], !state.settled, state.running == nil,
                let demand = state.pending, demand.dueAt <= now
            else { continue }
            sequence += 1
            let look = RunningLook(
                scope: newScope(pane), sequence: sequence, taskId: taskId,
                requiredIdentity: demand.requiredIdentity, quitting: demand.quitting)
            state.pending = nil
            state.running = look
            panes[pane] = state
            looks[pane] = look
            factSink(look.scope, .snapshotStarted(sequence: look.sequence))
        }
        if !looks.isEmpty {
            let captured = looks
            tasks[taskId] = Task { [weak self] in
                await self?.executeLooks(captured)
                await self?.taskFinished(taskId)
            }
        }
        rescheduleDeadline()
    }

    private func executeLooks(_ looks: [UUID: RunningLook]) async {
        do {
            let bindings = try await repository.eligiblePanes().filter { looks[$0.paneId] != nil }
            try Task.checkCancellation()
            let snapshots = try await probe.probeForeground(of: bindings.map(\.sessionId))
            for (paneId, look) in looks {
                guard let binding = bindings.first(where: { $0.paneId == paneId }),
                    let snapshot = snapshots[binding.sessionId]
                else {
                    completeLook(paneId, look: look)
                    continue
                }
                await admitSnapshot(snapshot, binding: binding, look: look)
            }
        } catch {
            for (paneId, look) in looks { completeLook(paneId, look: look) }
        }
    }

    private func isCurrent(_ look: RunningLook) -> Bool {
        !stopped && !retiredPanes.contains(look.scope.paneId)
            && panes[look.scope.paneId]?.settled != true
            && panes[look.scope.paneId]?.running?.scope == look.scope
    }

    private func admitSnapshot(_ snapshot: ForegroundSnapshot, binding: ForegroundPaneBinding, look: RunningLook) async
    {
        guard isCurrent(look) else { return }
        if let identity = look.requiredIdentity, identity != snapshot.sessionIdentity {
            completeLook(binding.paneId, look: look)
            return
        }
        let observation = PaneForegroundObservation(
            paneId: binding.paneId, zmxSessionId: binding.sessionId, sessionIdentity: snapshot.sessionIdentity,
            bindingGenerationId: binding.bindingGenerationId, program: snapshot.program,
            observerLaunchId: observerLaunchId, sequence: look.sequence, observedAt: Date())
        do {
            let admission = try await repository.admit(observation)
            guard isCurrent(look) else { return }
            factSink(look.scope, .observation(admission))
            if admission == .admitted {
                // The repository remains authoritative after any suspension.
                let latest = try await repository.load(paneId: binding.paneId)
                guard isCurrent(look) else { return }
                if latest?.observerLaunchId == observerLaunchId, latest?.sequence == look.sequence {
                    replaceWatch(snapshot: snapshot, binding: binding, look: look)
                }
            }
        } catch {}
        completeLook(binding.paneId, look: look)
    }

    private func replaceWatch(snapshot: ForegroundSnapshot, binding: ForegroundPaneBinding, look: RunningLook) {
        removeWatch(binding.paneId)
        guard !look.quitting, snapshot.program == .claudeCode || snapshot.program == .codex,
            let process = snapshot.foregroundProcess, isCurrent(look)
        else { return }
        let watchId = UUIDv7.generate()
        let listenerId = UUIDv7.generate()
        let watch = exitWatcher.watchExit(of: process, watchId: watchId)
        panes[binding.paneId]?.watch = OwnedWatch(
            value: .init(watchId: watchId, incarnation: process, bindingGenerationId: binding.bindingGenerationId),
            identity: snapshot.sessionIdentity, cancel: watch.cancel, listenerId: listenerId)
        factSink(look.scope, .watchRegistered(watchId: watchId))
        tasks[listenerId] = Task { [weak self] in
            for await event in watch.events { await self?.watchEvent(event, paneId: binding.paneId) }
            await self?.taskFinished(listenerId)
        }
    }

    private func watchEvent(_ event: ProcessExitWatchEvent, paneId: UUID) {
        let watchId: UUID
        switch event {
        case .exited(let identifier), .alreadyGone(let identifier), .unavailable(let identifier, _):
            watchId = identifier
        }
        let scope = ForegroundObserverFactScope(paneId: paneId, operationId: watchId)
        guard !stopped, !retiredPanes.contains(paneId), let watch = panes[paneId]?.watch,
            watch.value.watchId == watchId
        else {
            factSink(scope, .staleWatchDropped(watchId: watchId))
            factSink(scope, .closed(.looked))
            return
        }
        // Clear the guard before cancellation: an already-read old callback
        // can still arrive, but cannot request another look or touch a record.
        removeWatch(paneId)
        guard var state = panes[paneId], !state.settled else { return }
        switch event {
        case .unavailable(_, let failure):
            factSink(scope, .watchUnavailable(failure))
            mergeDemand(into: &state, due: clock.now.advanced(by: policy.lookMaxDelay), identity: nil, quitting: false)
        case .exited, .alreadyGone:
            mergeDemand(into: &state, due: clock.now, identity: watch.identity, quitting: false)
        }
        panes[paneId] = state
        factSink(scope, .closed(.looked))
        rescheduleDeadline()
    }

    private func removeWatch(_ paneId: UUID) {
        guard let watch = panes[paneId]?.watch else { return }
        panes[paneId]?.watch = nil
        watch.cancel()
        tasks[watch.listenerId]?.cancel()
    }

    private func completeLook(_ paneId: UUID, look: RunningLook) {
        guard isCurrent(look), var state = panes[paneId] else { return }
        state.running = nil
        if look.quitting {
            removeWatch(paneId)
            state.watch = nil
            state.settled = true
            state.pending = nil
            state.followUp = nil
            state.quitDeadline = nil
        } else if let followUp = state.followUp {
            state.pending = followUp
            state.followUp = nil
        } else if state.outputActive != nil {
            let due = clock.now.advanced(by: policy.lookMaxDelay)
            state.pending = Demand(dueAt: due, maxAt: due, requiredIdentity: nil, quitting: false)
        }
        panes[paneId] = state
        factSink(look.scope, .closed(look.quitting ? .quit : .looked))
        rescheduleDeadline()
    }

    private func settleQuitDeadline(_ paneId: UUID) {
        guard var state = panes[paneId], !state.settled else { return }
        removeWatch(paneId)
        state.watch = nil
        let scope = state.running?.scope ?? newScope(paneId)
        let taskId = state.running?.taskId
        state.running = nil
        state.pending = nil
        state.followUp = nil
        state.quitDeadline = nil
        state.settled = true
        panes[paneId] = state
        cancelLookIfUnused(taskId)
        factSink(scope, .closed(.quitDeadline))
    }

    package func retire(paneId: UUID) async {
        guard retiredPanes.insert(paneId).inserted else { return }
        removeWatch(paneId)
        let scope = panes[paneId]?.running?.scope ?? newScope(paneId)
        let taskId = panes[paneId]?.running?.taskId
        panes[paneId] = nil
        cancelLookIfUnused(taskId)
        try? await repository.retire(paneId: paneId)
        factSink(scope, .closed(.retired))
        rescheduleDeadline()
    }

    package func takePreRestoreObservation(paneId: UUID) async throws -> PaneForegroundObservation? {
        guard !retiredPanes.contains(paneId), handoffs.insert(paneId).inserted else { return nil }
        return try await repository.load(paneId: paneId)
    }

    package func currentWatch(paneId: UUID) -> CurrentExitWatch? { panes[paneId]?.watch?.value }

    package func shutdown() async {
        guard !stopped else {
            for task in Array(tasks.values) { await task.value }
            return
        }
        stopped = true
        deadlineTaskId = nil
        for pane in Array(panes.keys) {
            removeWatch(pane)
            if let look = panes[pane]?.running { factSink(look.scope, .closed(.quit)) }
        }
        panes.removeAll()
        let owned = Array(tasks.values)
        for task in owned { task.cancel() }
        for task in owned { await task.value }
        tasks.removeAll()
    }

    private func cancelLookIfUnused(_ identifier: UUID?) {
        guard let identifier, !panes.values.contains(where: { $0.running?.taskId == identifier }) else { return }
        tasks[identifier]?.cancel()
    }

    private func taskFinished(_ identifier: UUID) { tasks[identifier] = nil }
    private func newScope(_ paneId: UUID) -> ForegroundObserverFactScope {
        .init(paneId: paneId, operationId: UUIDv7.generate())
    }
}
