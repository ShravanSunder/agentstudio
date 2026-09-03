import CoreServices
import Foundation

package struct DarwinSharedLocalFSEventObservationSnapshot: Equatable, Sendable {
    package let physicalStreamCount: Int
    package let logicalRegistrationCount: Int
    package let physicalStreamCountByVolume: [UInt64: Int]
}

private struct DarwinSharedLocalFSEventRegistrationKey: Hashable, Sendable {
    let worktreeID: UUID
    let lifecycleGeneration: UInt64
}

private struct DarwinSharedLocalFSEventRegistration: @unchecked Sendable {
    let watchedPaths: [String]
    let eventHandler: @Sendable ([DarwinLocalFSEventRawEvent]) -> Void
}

private struct DarwinSharedLocalFSEventObserver: @unchecked Sendable {
    let generation: UInt64
    let watchedPaths: [String]
    var privateStagingExclusionPaths: [String]
    let streamLifetime: any DarwinLocalFSEventStreamLifetime
    var registrationKeys: Set<DarwinSharedLocalFSEventRegistrationKey>
}

/// Inputs one `bind` computes under `configurationLock` before choosing to
/// join the current physical stream or replace it.
private struct DarwinSharedLocalFSEventBindingPlan: @unchecked Sendable {
    let request: DarwinLocalFSEventStreamRequest
    let registrationKey: DarwinSharedLocalFSEventRegistrationKey
    let registration: DarwinSharedLocalFSEventRegistration
    let volumeSystemNumber: UInt64
    let existingObserver: DarwinSharedLocalFSEventObserver?
    let desiredWatchedPaths: [String]
    let desiredExclusionPaths: [String]
}

/// Owns a bounded set of physical local FSEvents streams while preserving
/// independent logical registrations for worktree routing and continuity.
package final class DarwinSharedLocalFSEventObserverRegistry: @unchecked Sendable {
    private let configurationLock = NSLock()
    private let stateLock = NSLock()
    private let streamFactory: DarwinLocalFSEventStreamFactory
    private let recordPhysicalRawCallback: @Sendable (Int) -> Void

    private var hasShutdown = false
    private var nextPhysicalGeneration: UInt64 = 0
    private var observerByVolume: [UInt64: DarwinSharedLocalFSEventObserver] = [:]
    private var registrationByKey: [DarwinSharedLocalFSEventRegistrationKey: DarwinSharedLocalFSEventRegistration] = [:]
    private var volumeByRegistrationKey: [DarwinSharedLocalFSEventRegistrationKey: UInt64] = [:]
    private var pendingGenerationByVolume: [UInt64: UInt64] = [:]
    private var pendingEventsByGeneration: [UInt64: [DarwinLocalFSEventRawEvent]] = [:]

    package init(
        streamFactory: @escaping DarwinLocalFSEventStreamFactory,
        recordPhysicalRawCallback: @escaping @Sendable (Int) -> Void
    ) {
        self.streamFactory = streamFactory
        self.recordPhysicalRawCallback = recordPhysicalRawCallback
    }

    deinit {
        shutdown()
    }

    package func bind(
        request: DarwinLocalFSEventStreamRequest
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        guard
            let volumeSystemNumber = request.watchedPaths.first.flatMap(
                DarwinFSEventBindingPlanner.volumeSystemNumber(for:)
            )
        else {
            return nil
        }

        configurationLock.lock()
        defer { configurationLock.unlock() }

        let registrationKey = DarwinSharedLocalFSEventRegistrationKey(
            worktreeID: request.worktreeId,
            lifecycleGeneration: request.lifecycleGeneration
        )
        let registration = DarwinSharedLocalFSEventRegistration(
            watchedPaths: Self.distinctWatchedPaths(request.watchedPaths),
            eventHandler: request.eventHandler
        )

        let bindingState = stateLock.withLock {
            (
                mayBind: !hasShutdown && registrationByKey[registrationKey] == nil,
                existingObserver: observerByVolume[volumeSystemNumber]
            )
        }
        guard bindingState.mayBind else { return nil }
        let existingObserver = bindingState.existingObserver

        let desiredWatchedPaths = Self.distinctWatchedPaths(
            (existingObserver?.watchedPaths ?? []) + registration.watchedPaths
        )
        let desiredExclusionPaths = Array(
            Set(existingObserver?.privateStagingExclusionPaths ?? [])
                .union(request.privateStagingExclusionPaths)
        ).sorted()

        let bindingPlan = DarwinSharedLocalFSEventBindingPlan(
            request: request,
            registrationKey: registrationKey,
            registration: registration,
            volumeSystemNumber: volumeSystemNumber,
            existingObserver: existingObserver,
            desiredWatchedPaths: desiredWatchedPaths,
            desiredExclusionPaths: desiredExclusionPaths
        )
        if let existingObserver,
            existingObserver.watchedPaths == desiredWatchedPaths
        {
            return joinObserverWithUnchangedPaths(existingObserver, plan: bindingPlan)
        }
        return replacePhysicalObserver(plan: bindingPlan)
    }

    /// Caller holds `configurationLock`.
    private func joinObserverWithUnchangedPaths(
        _ existingObserver: DarwinSharedLocalFSEventObserver,
        plan: DarwinSharedLocalFSEventBindingPlan
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        var joinedObserver = existingObserver
        joinedObserver.registrationKeys.insert(plan.registrationKey)
        joinedObserver.privateStagingExclusionPaths = plan.desiredExclusionPaths
        stateLock.withLock {
            guard !hasShutdown else { return }
            registrationByKey[plan.registrationKey] = plan.registration
            volumeByRegistrationKey[plan.registrationKey] = plan.volumeSystemNumber
            observerByVolume[plan.volumeSystemNumber] = joinedObserver
        }
        guard stateLock.withLock({ registrationByKey[plan.registrationKey] != nil }) else {
            return nil
        }
        return DarwinSharedLocalFSEventRegistrationLease(
            registry: self,
            registrationKey: plan.registrationKey
        )
    }

    /// Caller holds `configurationLock`. Starts a replacement physical stream
    /// for the widened path set, drains the predecessor, and installs the
    /// replacement atomically.
    private func replacePhysicalObserver(
        plan: DarwinSharedLocalFSEventBindingPlan
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        let volumeSystemNumber = plan.volumeSystemNumber
        let existingObserver = plan.existingObserver
        let physicalGeneration = stateLock.withLock { () -> UInt64 in
            nextPhysicalGeneration &+= 1
            let generation = nextPhysicalGeneration
            pendingGenerationByVolume[volumeSystemNumber] = generation
            pendingEventsByGeneration[generation] = []
            return generation
        }
        let physicalRequest = DarwinLocalFSEventStreamRequest(
            worktreeId: plan.request.worktreeId,
            lifecycleGeneration: physicalGeneration,
            watchedPaths: plan.desiredWatchedPaths,
            // A physical stream can cover more than eight repositories, while
            // FSEventStreamSetExclusionPaths accepts at most eight paths.
            // Contract Agent Studio's private staged refs once in `receive`
            // instead of making native stream availability depend on repo count.
            privateStagingExclusionPaths: [],
            eventHandler: { [weak self] rawEvents in
                self?.receive(
                    volumeSystemNumber: volumeSystemNumber,
                    physicalGeneration: physicalGeneration,
                    rawEvents: rawEvents
                )
            }
        )
        guard let replacementLifetime = streamFactory(physicalRequest) else {
            clearPendingGeneration(
                physicalGeneration,
                volumeSystemNumber: volumeSystemNumber
            )
            return nil
        }

        // The replacement begins at `sinceNow`. Flush the still-current
        // predecessor before installing it: events before replacement start
        // drain through the predecessor, while replacement callbacks buffer
        // until the atomic handoff below.
        if let existingObserver, !existingObserver.streamLifetime.flush() {
            replacementLifetime.retire()
            clearPendingGeneration(
                physicalGeneration,
                volumeSystemNumber: volumeSystemNumber
            )
            return nil
        }

        var retiredLifetime: (any DarwinLocalFSEventStreamLifetime)?
        let bufferedEvents = stateLock.withLock { () -> [DarwinLocalFSEventRawEvent]? in
            guard !hasShutdown,
                pendingGenerationByVolume[volumeSystemNumber] == physicalGeneration
            else {
                pendingEventsByGeneration.removeValue(forKey: physicalGeneration)
                return nil
            }
            registrationByKey[plan.registrationKey] = plan.registration
            volumeByRegistrationKey[plan.registrationKey] = volumeSystemNumber
            var registrationKeys = existingObserver?.registrationKeys ?? []
            registrationKeys.insert(plan.registrationKey)
            retiredLifetime = existingObserver?.streamLifetime
            observerByVolume[volumeSystemNumber] = DarwinSharedLocalFSEventObserver(
                generation: physicalGeneration,
                watchedPaths: plan.desiredWatchedPaths,
                privateStagingExclusionPaths: plan.desiredExclusionPaths,
                streamLifetime: replacementLifetime,
                registrationKeys: registrationKeys
            )
            pendingGenerationByVolume.removeValue(forKey: volumeSystemNumber)
            return pendingEventsByGeneration.removeValue(forKey: physicalGeneration) ?? []
        }
        guard let bufferedEvents else {
            replacementLifetime.retire()
            return nil
        }
        retiredLifetime?.retire()
        if !bufferedEvents.isEmpty {
            receive(
                volumeSystemNumber: volumeSystemNumber,
                physicalGeneration: physicalGeneration,
                rawEvents: bufferedEvents
            )
        }
        return DarwinSharedLocalFSEventRegistrationLease(
            registry: self,
            registrationKey: plan.registrationKey
        )
    }

    package func snapshot() -> DarwinSharedLocalFSEventObservationSnapshot {
        stateLock.withLock {
            DarwinSharedLocalFSEventObservationSnapshot(
                physicalStreamCount: observerByVolume.count,
                logicalRegistrationCount: registrationByKey.count,
                physicalStreamCountByVolume: Dictionary(
                    uniqueKeysWithValues: observerByVolume.keys.map { ($0, 1) }
                )
            )
        }
    }

    package func flushAllPhysicalStreams() -> Bool {
        let retainedObservers = stateLock.withLock { () -> [(UInt64, UInt64, any DarwinLocalFSEventStreamLifetime)]? in
            guard !hasShutdown else { return nil }
            return observerByVolume.map { volumeSystemNumber, observer in
                (volumeSystemNumber, observer.generation, observer.streamLifetime)
            }
        }
        guard let retainedObservers else { return false }
        for (volumeSystemNumber, generation, streamLifetime) in retainedObservers {
            guard streamLifetime.flush() else { return false }
            guard
                stateLock.withLock({
                    !hasShutdown && observerByVolume[volumeSystemNumber]?.generation == generation
                })
            else {
                return false
            }
        }
        return true
    }

    package func shutdown() {
        configurationLock.lock()
        let streamLifetimes = stateLock.withLock { () -> [any DarwinLocalFSEventStreamLifetime] in
            guard !hasShutdown else { return [] }
            hasShutdown = true
            let lifetimes = observerByVolume.values.map(\.streamLifetime)
            observerByVolume.removeAll(keepingCapacity: false)
            registrationByKey.removeAll(keepingCapacity: false)
            volumeByRegistrationKey.removeAll(keepingCapacity: false)
            pendingGenerationByVolume.removeAll(keepingCapacity: false)
            pendingEventsByGeneration.removeAll(keepingCapacity: false)
            return lifetimes
        }
        configurationLock.unlock()
        for streamLifetime in streamLifetimes {
            streamLifetime.retire()
        }
    }

    fileprivate func flush(
        registrationKey: DarwinSharedLocalFSEventRegistrationKey
    ) -> Bool {
        let retainedObserver = stateLock.withLock {
            guard !hasShutdown,
                registrationByKey[registrationKey] != nil,
                let volumeSystemNumber = volumeByRegistrationKey[registrationKey],
                let observer = observerByVolume[volumeSystemNumber]
            else {
                return Optional<(UInt64, UInt64, any DarwinLocalFSEventStreamLifetime)>.none
            }
            return (volumeSystemNumber, observer.generation, observer.streamLifetime)
        }
        guard let (volumeSystemNumber, generation, streamLifetime) = retainedObserver,
            streamLifetime.flush()
        else {
            return false
        }
        return stateLock.withLock {
            !hasShutdown
                && registrationByKey[registrationKey] != nil
                && volumeByRegistrationKey[registrationKey] == volumeSystemNumber
                && observerByVolume[volumeSystemNumber]?.generation == generation
        }
    }

    fileprivate func unbind(
        registrationKey: DarwinSharedLocalFSEventRegistrationKey
    ) {
        configurationLock.lock()
        var retiredLifetime: (any DarwinLocalFSEventStreamLifetime)?
        stateLock.withLock {
            guard let volumeSystemNumber = volumeByRegistrationKey.removeValue(forKey: registrationKey) else {
                return
            }
            registrationByKey.removeValue(forKey: registrationKey)
            guard var observer = observerByVolume[volumeSystemNumber] else { return }
            observer.registrationKeys.remove(registrationKey)
            if observer.registrationKeys.isEmpty {
                observerByVolume.removeValue(forKey: volumeSystemNumber)
                retiredLifetime = observer.streamLifetime
            } else {
                observerByVolume[volumeSystemNumber] = observer
            }
        }
        configurationLock.unlock()
        retiredLifetime?.retire()
    }

    fileprivate func scheduleUnbind(
        registrationKey: DarwinSharedLocalFSEventRegistrationKey
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.unbind(registrationKey: registrationKey)
        }
    }

    private func clearPendingGeneration(
        _ generation: UInt64,
        volumeSystemNumber: UInt64
    ) {
        stateLock.withLock {
            if pendingGenerationByVolume[volumeSystemNumber] == generation {
                pendingGenerationByVolume.removeValue(forKey: volumeSystemNumber)
            }
            pendingEventsByGeneration.removeValue(forKey: generation)
        }
    }

    private func receive(
        volumeSystemNumber: UInt64,
        physicalGeneration: UInt64,
        rawEvents: [DarwinLocalFSEventRawEvent]
    ) {
        guard !rawEvents.isEmpty else { return }
        recordPhysicalRawCallback(rawEvents.count)

        let routingState = stateLock.withLock {
            () -> ([DarwinSharedLocalFSEventRegistration], [String])? in
            if pendingGenerationByVolume[volumeSystemNumber] == physicalGeneration {
                pendingEventsByGeneration[physicalGeneration, default: []].append(contentsOf: rawEvents)
                return nil
            }
            guard !hasShutdown,
                let observer = observerByVolume[volumeSystemNumber],
                observer.generation == physicalGeneration
            else {
                return nil
            }
            return (
                observer.registrationKeys.compactMap { registrationByKey[$0] },
                observer.privateStagingExclusionPaths
            )
        }
        guard let (registrations, privateStagingExclusionPaths) = routingState else { return }
        let admittedRawEvents = rawEvents.filter { event in
            if Self.isBroadcastUncertainty(event) {
                return true
            }
            let eventPath = DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath(event.path)
            return !privateStagingExclusionPaths.contains { exclusionPath in
                Self.containsPath(eventPath, root: exclusionPath)
            }
        }
        guard !admittedRawEvents.isEmpty else { return }

        for registration in registrations {
            let matchingEvents = admittedRawEvents.filter { event in
                Self.requiresDelivery(
                    event,
                    watchedPaths: registration.watchedPaths
                )
            }
            if !matchingEvents.isEmpty {
                registration.eventHandler(matchingEvents)
            }
        }
    }

    private static func requiresDelivery(
        _ event: DarwinLocalFSEventRawEvent,
        watchedPaths: [String]
    ) -> Bool {
        if isBroadcastUncertainty(event) {
            return true
        }
        let eventPath = DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath(event.path)
        if event.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            return watchedPaths.contains { watchedPath in
                containsPath(watchedPath, root: eventPath)
            }
        }
        return watchedPaths.contains { watchedPath in
            pathsIntersect(eventPath, watchedPath)
        }
    }

    private static func isBroadcastUncertainty(
        _ event: DarwinLocalFSEventRawEvent
    ) -> Bool {
        event.flags & broadcastUncertaintyFlags != 0
    }

    private static func pathsIntersect(_ lhs: String, _ rhs: String) -> Bool {
        containsPath(lhs, root: rhs)
            || containsPath(rhs, root: lhs)
    }

    private static func containsPath(
        _ candidate: String,
        root: String
    ) -> Bool {
        candidate == root || (root == "/" ? candidate.hasPrefix("/") : candidate.hasPrefix(root + "/"))
    }

    private static func distinctWatchedPaths(_ paths: [String]) -> [String] {
        Array(
            Set(paths.map(DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath))
        ).sorted()
    }

    private static let broadcastUncertaintyFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagMount
            | kFSEventStreamEventFlagUnmount
    )
}

private final class DarwinSharedLocalFSEventRegistrationLease:
    DarwinLocalFSEventStreamLifetime, @unchecked Sendable
{
    private let retirementLock = NSLock()
    private weak var registry: DarwinSharedLocalFSEventObserverRegistry?
    private let registrationKey: DarwinSharedLocalFSEventRegistrationKey
    private var didRetire = false

    init(
        registry: DarwinSharedLocalFSEventObserverRegistry,
        registrationKey: DarwinSharedLocalFSEventRegistrationKey
    ) {
        self.registry = registry
        self.registrationKey = registrationKey
    }

    deinit {
        retire()
    }

    func flush() -> Bool {
        guard retirementLock.withLock({ !didRetire }) else { return false }
        return registry?.flush(registrationKey: registrationKey) == true
    }

    func retire() {
        if claimRetirement() {
            registry?.unbind(registrationKey: registrationKey)
        }
    }

    func scheduleRetirement() {
        if claimRetirement() {
            registry?.scheduleUnbind(registrationKey: registrationKey)
        }
    }

    private func claimRetirement() -> Bool {
        retirementLock.withLock {
            guard !didRetire else { return false }
            didRetire = true
            return true
        }
    }
}
