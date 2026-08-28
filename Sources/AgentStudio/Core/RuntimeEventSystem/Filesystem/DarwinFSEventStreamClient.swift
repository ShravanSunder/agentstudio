import AgentStudioGit
import AgentStudioInfrastructure
import CoreServices
import Foundation

private final class CallbackContext {
    weak var client: DarwinFSEventStreamClient?
    let worktreeId: UUID
    let lifecycleGeneration: UInt64

    init(client: DarwinFSEventStreamClient, worktreeId: UUID, lifecycleGeneration: UInt64) {
        self.client = client
        self.worktreeId = worktreeId
        self.lifecycleGeneration = lifecycleGeneration
    }
}

private struct StreamRegistration: @unchecked Sendable {
    let lifecycleGeneration: UInt64
    let participant: FSEventParticipant
    let rootPath: URL
    let observationIdentity: AgentStudioGit.GitStatusObservationIdentity?
    let observationScopes: [AgentStudioGit.GitStatusObservationScope]
    let watchedPaths: [String]
    let streamLifetime: DarwinFSEventNativeStreamLifetime
}

private struct CompositeStreamRetention {
    let registration: StreamRegistration
    let sharedBindingLease: DarwinSharedExactItemBindingLease?
}

private struct LocalEventClassificationInput {
    let rootPath: String
    let participant: FSEventParticipant
    let observesContinuity: Bool
    let scopes: [AgentStudioGit.GitStatusObservationScope]
}

/// Production filesystem event client wiring point.
package final class DarwinFSEventStreamClient: FSEventStreamClient, GitCleanContinuityWitness,
    @unchecked Sendable
{
    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
        guard let info else { return }

        let context = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
        guard let client = context.client else { return }

        let pathArray = unsafeBitCast(paths, to: CFArray.self)
        let pathCount = CFArrayGetCount(pathArray)
        let boundedCount = min(Int(count), pathCount)
        var changedPaths: [String] = []
        var rawEvents: [(path: String, eventId: FSEventStreamEventId, flags: FSEventStreamEventFlags)] = []
        changedPaths.reserveCapacity(boundedCount)
        rawEvents.reserveCapacity(boundedCount)
        for index in 0..<boundedCount {
            let value = CFArrayGetValueAtIndex(pathArray, index)
            guard let value else { continue }
            let path = unsafeBitCast(value, to: CFString.self) as String
            changedPaths.append(path)
            rawEvents.append((path: path, eventId: ids[index], flags: flags[index]))
        }
        client.ingressPerformanceAccumulator.recordLocalRawCallback(eventCount: rawEvents.count)
        client.emitRawEvents(
            worktreeId: context.worktreeId,
            lifecycleGeneration: context.lifecycleGeneration,
            rawEvents: rawEvents,
            ordinaryPaths: changedPaths
        )
    }

    private static let defaultLatency: CFTimeInterval = 0.1

    let lifecycleLock = NSLock()
    private var hasShutdown = false
    var hasStoppedActivityAdmission = false
    private var nextLifecycleGeneration: UInt64 = 0
    private var streamByWorktreeId: [UUID: StreamRegistration] = [:]
    private var latestEventIDByParticipant: [FSEventParticipant: UInt64] = [:]
    let ingressBuffer: DarwinFSEventIngressBuffer
    private let continuityLedger: GitCleanContinuityLedger
    let sharedExactItemObserverRegistry: DarwinSharedExactItemObserverRegistry
    private let sharedExactItemFingerprintReader: DarwinSharedExactItemFingerprintReader
    private let ingressPerformanceAccumulator: DarwinFSEventIngressPerformanceAccumulator

    package init(
        bufferedFineBatchCapacity: Int = AppPolicies.FilesystemIngress.bufferedFineBatchCapacity,
        sharedExactItemStreamFactory: @escaping DarwinSharedExactItemStreamFactory =
            DarwinSharedExactItemNativeStream.start,
        sharedExactItemFingerprintReader: DarwinSharedExactItemFingerprintReader = .init()
    ) {
        let continuityLedger = GitCleanContinuityLedger()
        let ingressPerformanceAccumulator = DarwinFSEventIngressPerformanceAccumulator()
        let ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: bufferedFineBatchCapacity,
            performanceAccumulator: ingressPerformanceAccumulator,
            overflowHandler: { worktreeId in
                continuityLedger.markUncertain(registrationId: worktreeId)
            }
        )
        self.continuityLedger = continuityLedger
        self.ingressBuffer = ingressBuffer
        self.ingressPerformanceAccumulator = ingressPerformanceAccumulator
        self.sharedExactItemFingerprintReader = sharedExactItemFingerprintReader
        sharedExactItemObserverRegistry = DarwinSharedExactItemObserverRegistry(
            streamFactory: sharedExactItemStreamFactory,
            recordRawEvents: { worktreeId, events in
                continuityLedger.recordRawEvents(
                    registrationId: worktreeId,
                    events: events
                )
            },
            recordAncestorAmbiguity: { worktreeId in
                continuityLedger.recordAncestorAmbiguity(registrationId: worktreeId)
            },
            authorityIsCurrentForAncestorRecheck: { authority in
                continuityLedger.authorityIsCurrentForAncestorRecheck(authority)
            },
            currentObservedAncestorAmbiguityEpoch: { authority in
                continuityLedger.currentObservedAncestorAmbiguityEpoch(
                    expectedAuthority: authority
                )
            },
            resolveAncestorAmbiguity: { authority, observedEpoch in
                continuityLedger.resolveAncestorAmbiguity(
                    expectedAuthority: authority,
                    expectedObservedEpoch: observedEpoch
                )
            },
            markUncertain: { worktreeId in
                continuityLedger.markUncertain(registrationId: worktreeId)
            },
            yieldFullGitRefresh: { worktreeId, source in
                ingressBuffer.yield(
                    FSEventBatch(
                        worktreeId: worktreeId,
                        paths: [],
                        requiresFullGitRefresh: true
                    ),
                    source: source
                )
            },
            yieldActivityObservations: { activityBatch in
                ingressBuffer.yieldActivityObservations(activityBatch)
            },
            performanceAccumulator: ingressPerformanceAccumulator,
            fingerprintReader: sharedExactItemFingerprintReader
        )
    }

    deinit {
        shutdown()
    }

    package func events() -> AsyncStream<FSEventIngressItem> {
        ingressBuffer.events()
    }

    package func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] {
        ingressBuffer.consumeOverflowRecoveries()
    }

    package func snapshotAndResetIngressPerformance() -> DarwinFSEventIngressPerformanceSnapshot {
        ingressPerformanceAccumulator.snapshotAndReset()
    }

    package func register(worktreeId: UUID, repoId _: UUID, rootPath: URL) {
        let canonicalRootPath = DarwinFSEventPathCanonicalizer.canonicalURL(rootPath)

        var registrationToTearDown: StreamRegistration?
        lifecycleLock.lock()
        if hasShutdown {
            lifecycleLock.unlock()
            return
        }
        if let existing = streamByWorktreeId[worktreeId] {
            if existing.rootPath == canonicalRootPath {
                lifecycleLock.unlock()
                return
            }
            streamByWorktreeId.removeValue(forKey: worktreeId)
            latestEventIDByParticipant.removeValue(forKey: existing.participant)
            registrationToTearDown = existing
        }
        lifecycleLock.unlock()

        if let registrationToTearDown {
            continuityLedger.unregister(registrationId: worktreeId)
            sharedExactItemObserverRegistry.unbind(
                worktreeId: worktreeId,
                bindingGeneration: registrationToTearDown.lifecycleGeneration
            )
            Self.teardown(registrationToTearDown)
        }

        guard
            let registration = makeRegistration(
                worktreeId: worktreeId,
                lifecycleGeneration: allocateLifecycleGeneration(),
                rootPath: canonicalRootPath,
                observationIdentity: nil,
                observationScopes: [],
                watchedPaths: [canonicalRootPath.path]
            )
        else {
            return
        }

        lifecycleLock.lock()
        if hasShutdown {
            lifecycleLock.unlock()
            Self.teardown(registration)
            return
        }
        if let existing = streamByWorktreeId.updateValue(registration, forKey: worktreeId) {
            lifecycleLock.unlock()
            Self.teardown(existing)
            return
        }
        lifecycleLock.unlock()
    }

    package func unregister(worktreeId: UUID) {
        continuityLedger.unregister(registrationId: worktreeId)
        let registration: StreamRegistration?
        lifecycleLock.lock()
        registration = streamByWorktreeId.removeValue(forKey: worktreeId)
        if let registration {
            latestEventIDByParticipant.removeValue(forKey: registration.participant)
        }
        lifecycleLock.unlock()

        sharedExactItemObserverRegistry.unbind(
            worktreeId: worktreeId,
            bindingGeneration: registration?.lifecycleGeneration
        )

        if let registration {
            Self.teardown(registration)
        }
    }

    package func shutdown() {
        let registrations: [StreamRegistration]
        lifecycleLock.lock()
        if hasShutdown {
            lifecycleLock.unlock()
            return
        }
        hasShutdown = true
        registrations = Array(streamByWorktreeId.values)
        streamByWorktreeId.removeAll(keepingCapacity: false)
        latestEventIDByParticipant.removeAll(keepingCapacity: false)
        lifecycleLock.unlock()

        for registration in registrations {
            Self.teardown(registration)
        }
        continuityLedger.shutdown()
        sharedExactItemObserverRegistry.shutdown()
        ingressBuffer.finish()
    }

    @concurrent
    nonisolated package func prepare(
        worktreeId: UUID,
        rootPath: URL,
        observationPlan: AgentStudioGit.GitStatusObservationPlan
    ) async -> GitCleanContinuityBarrier? {
        guard observationPlan.support == .supported else { return nil }
        let canonicalRootPath = DarwinFSEventPathCanonicalizer.canonicalURL(rootPath)
        guard
            let binding = DarwinFSEventBindingPlanner.plan(observationPlan: observationPlan)
        else { return nil }
        let observationIdentity = observationPlan.identity

        let currentRegistration = retainedRegistration(worktreeId: worktreeId)
        guard let currentRegistration, currentRegistration.rootPath == canonicalRootPath else { return nil }

        let registration: StreamRegistration
        if currentRegistration.observationIdentity == observationIdentity,
            currentRegistration.watchedPaths == binding.localWatchedPaths,
            DarwinFSEventBindingPlanner.scopesMatch(
                currentRegistration.observationScopes,
                binding.localScopes
            )
        {
            continuityLedger.register(
                registrationId: worktreeId,
                identity: observationIdentity,
                preserveAncestorAmbiguity: true
            )
            registration = currentRegistration
        } else {
            continuityLedger.unregister(registrationId: worktreeId)
            guard
                let replacement = makeRegistration(
                    worktreeId: worktreeId,
                    lifecycleGeneration: allocateLifecycleGeneration(),
                    rootPath: canonicalRootPath,
                    observationIdentity: observationIdentity,
                    observationScopes: binding.localScopes,
                    watchedPaths: binding.localWatchedPaths
                )
            else {
                return nil
            }

            let installed = lifecycleLock.withLock { () -> Bool in
                guard !hasShutdown,
                    streamByWorktreeId[worktreeId]?.lifecycleGeneration
                        == currentRegistration.lifecycleGeneration
                else {
                    return false
                }
                streamByWorktreeId[worktreeId] = replacement
                return true
            }
            guard installed else {
                Self.teardown(replacement)
                continuityLedger.unregister(registrationId: worktreeId)
                return nil
            }
            Self.teardown(currentRegistration)
            registration = replacement
        }

        guard
            installSharedBinding(
                worktreeId: worktreeId,
                registration: registration,
                exactItemsByParent: binding.sharedExactItemsByParent
            )
        else {
            return nil
        }
        guard
            let preFlushBarrier = continuityLedger.beginBarrier(
                registrationId: worktreeId,
                identity: observationIdentity
            ),
            let streamRetention = retainCompositeStreams(
                worktreeId: worktreeId,
                observationIdentity: observationIdentity,
                requiresSharedBinding: !binding.sharedExactItemsByParent.isEmpty
            )
        else {
            return nil
        }
        guard flush(streamRetention) else { return nil }
        guard
            let postFlushBarrier = continuityLedger.beginBarrier(
                registrationId: worktreeId,
                identity: observationIdentity
            ),
            postFlushBarrier == preFlushBarrier,
            compositeStreamsAreCurrent(
                worktreeId: worktreeId,
                streamRetention: streamRetention
            )
        else {
            return nil
        }
        return postFlushBarrier
    }

    @concurrent
    nonisolated package func commit(
        _ barrier: GitCleanContinuityBarrier
    ) async -> GitCleanContinuityAuthorityValidation {
        guard
            let streamRetention = retainCompositeStreams(
                worktreeId: barrier.registrationId,
                observationIdentity: barrier.observationIdentity,
                requiresSharedBinding: nil
            )
        else {
            return .requiresExact(.registrationMissing)
        }
        guard flush(streamRetention) else { return .requiresExact(.streamStartFailed) }
        guard
            continuityLedger.barrierIsCurrent(barrier) == nil,
            compositeStreamsAreCurrent(
                worktreeId: barrier.registrationId,
                streamRetention: streamRetention
            )
        else {
            return .requiresExact(
                continuityLedger.barrierIsCurrent(barrier) ?? .registrationReplaced
            )
        }

        guard let sharedBindingLease = streamRetention.sharedBindingLease else {
            return continuityLedger.commitBarrier(barrier)
        }
        let canonicalItemPaths = Array(
            Set(sharedBindingLease.exactItemsByParent.values.flatMap { $0 })
        ).sorted()
        let fingerprintOutcome = await sharedExactItemFingerprintReader.read(
            canonicalItemPaths: canonicalItemPaths
        )
        guard let fingerprintSnapshot = fingerprintOutcome.snapshot else {
            return .requiresExact(.eventStreamUncertain)
        }
        guard flush(streamRetention) else { return .requiresExact(.streamStartFailed) }
        guard
            continuityLedger.barrierIsCurrent(barrier) == nil,
            compositeStreamsAreCurrent(
                worktreeId: barrier.registrationId,
                streamRetention: streamRetention
            )
        else {
            return .requiresExact(
                continuityLedger.barrierIsCurrent(barrier) ?? .registrationReplaced
            )
        }

        let validation = continuityLedger.commitBarrier(barrier)
        guard case .authoritative(let authority) = validation else { return validation }
        guard
            sharedExactItemObserverRegistry.installAuthorityBaseline(
                worktreeId: barrier.registrationId,
                authority: authority,
                lease: sharedBindingLease,
                snapshot: fingerprintSnapshot
            ),
            compositeStreamsAreCurrent(
                worktreeId: barrier.registrationId,
                streamRetention: streamRetention
            ),
            continuityLedger.renew(authority) == .authoritative(authority),
            sharedExactItemObserverRegistry.authorityBaselineIsCurrent(
                worktreeId: barrier.registrationId,
                authority: authority,
                lease: sharedBindingLease
            )
        else {
            sharedExactItemObserverRegistry.clearAuthorityBaseline(
                worktreeId: barrier.registrationId
            )
            return .requiresExact(.registrationReplaced)
        }
        return validation
    }

    @concurrent
    nonisolated package func renew(
        _ authority: GitCleanContinuityAuthority
    ) async -> GitCleanContinuityAuthorityValidation {
        guard
            let streamRetention = retainCompositeStreams(
                worktreeId: authority.registrationId,
                observationIdentity: authority.observationIdentity,
                requiresSharedBinding: nil
            )
        else {
            return .requiresExact(.registrationMissing)
        }
        guard flush(streamRetention) else { return .requiresExact(.streamStartFailed) }
        guard
            compositeStreamsAreCurrent(
                worktreeId: authority.registrationId,
                streamRetention: streamRetention
            )
        else {
            return .requiresExact(.registrationReplaced)
        }
        let validation = continuityLedger.renew(authority)
        guard case .authoritative(let renewedAuthority) = validation else { return validation }
        if let sharedBindingLease = streamRetention.sharedBindingLease {
            guard
                sharedExactItemObserverRegistry.authorityBaselineIsCurrent(
                    worktreeId: authority.registrationId,
                    authority: renewedAuthority,
                    lease: sharedBindingLease
                )
            else {
                return .requiresExact(.eventStreamUncertain)
            }
        }
        return validation
    }

    package func retire(worktreeId: UUID, rootPath: URL) {
        let canonicalRootPath = DarwinFSEventPathCanonicalizer.canonicalURL(rootPath)
        let matches = lifecycleLock.withLock {
            streamByWorktreeId[worktreeId]?.rootPath == canonicalRootPath
        }
        if matches {
            sharedExactItemObserverRegistry.clearAuthorityBaseline(worktreeId: worktreeId)
            continuityLedger.unregister(registrationId: worktreeId)
        }
    }

    package func receiveLocalRawEvents(
        worktreeId: UUID,
        rawEvents: [(path: String, eventId: FSEventStreamEventId, flags: FSEventStreamEventFlags)]
    ) {
        guard
            let lifecycleGeneration = lifecycleLock.withLock({
                streamByWorktreeId[worktreeId]?.lifecycleGeneration
            })
        else {
            return
        }
        emitRawEvents(
            worktreeId: worktreeId,
            lifecycleGeneration: lifecycleGeneration,
            rawEvents: rawEvents,
            ordinaryPaths: rawEvents.map(\.path)
        )
    }

    private func makeRegistration(
        worktreeId: UUID,
        lifecycleGeneration: UInt64,
        rootPath: URL,
        observationIdentity: AgentStudioGit.GitStatusObservationIdentity?,
        observationScopes: [AgentStudioGit.GitStatusObservationScope],
        watchedPaths: [String]
    ) -> StreamRegistration? {
        let callbackContext = CallbackContext(
            client: self,
            worktreeId: worktreeId,
            lifecycleGeneration: lifecycleGeneration
        )
        let callbackContextPtr = Unmanaged.passRetained(callbackContext).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: callbackContextPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let watchPaths = watchedPaths.map { $0 as NSString } as CFArray
        guard
            let volumeSystemNumber = watchedPaths.first.flatMap(
                DarwinFSEventBindingPlanner.volumeSystemNumber(for:)
            )
        else {
            Unmanaged<CallbackContext>.fromOpaque(callbackContextPtr).release()
            return nil
        }
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.callback,
                &streamContext,
                watchPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.defaultLatency,
                DarwinFSEventStreamConfiguration.continuityFlags
            )
        else {
            Unmanaged<CallbackContext>.fromOpaque(callbackContextPtr).release()
            return nil
        }

        let queue = DispatchQueue(
            label: "com.agentstudio.fsevents.\(worktreeId.uuidString)",
            qos: .utility
        )
        FSEventStreamSetDispatchQueue(stream, queue)
        if let observationIdentity {
            continuityLedger.register(registrationId: worktreeId, identity: observationIdentity)
        }
        guard FSEventStreamStart(stream) else {
            continuityLedger.unregister(registrationId: worktreeId)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Unmanaged<CallbackContext>.fromOpaque(callbackContextPtr).release()
            return nil
        }
        let streamLifetime = DarwinFSEventNativeStreamLifetime(
            stream: stream,
            queue: queue,
            releaseCallbackContext: {
                Unmanaged<CallbackContext>.fromOpaque(callbackContextPtr).release()
            }
        )

        return StreamRegistration(
            lifecycleGeneration: lifecycleGeneration,
            participant: FSEventParticipant(
                scopeKey: "local:\(worktreeId.uuidString)",
                generation: lifecycleGeneration,
                volumeIdentifier: String(volumeSystemNumber)
            ),
            rootPath: rootPath,
            observationIdentity: observationIdentity,
            observationScopes: observationScopes,
            watchedPaths: watchedPaths,
            streamLifetime: streamLifetime
        )
    }

    private func emitRawEvents(
        worktreeId: UUID,
        lifecycleGeneration: UInt64,
        rawEvents: [(path: String, eventId: FSEventStreamEventId, flags: FSEventStreamEventFlags)],
        ordinaryPaths: [String]
    ) {
        guard !rawEvents.isEmpty else { return }
        guard lifecycleLock.withLock({ !hasShutdown && !hasStoppedActivityAdmission }) else {
            return
        }

        if rawEvents.contains(where: { event in
            event.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
        }) {
            retireRegistrationAfterRootChange(
                worktreeId: worktreeId,
                lifecycleGeneration: lifecycleGeneration,
                rawEvents: rawEvents,
                ordinaryPaths: ordinaryPaths
            )
            return
        }

        var registrationWasReplaced = false
        let classificationInput = lifecycleLock.withLock {
            guard !hasShutdown, !hasStoppedActivityAdmission,
                let registration = streamByWorktreeId[worktreeId]
            else {
                return Optional<LocalEventClassificationInput>.none
            }
            guard registration.lifecycleGeneration == lifecycleGeneration else {
                registrationWasReplaced = true
                return nil
            }
            if let latestEventID = rawEvents.map(\.eventId).max() {
                latestEventIDByParticipant[registration.participant] = max(
                    latestEventIDByParticipant[registration.participant] ?? 0,
                    UInt64(latestEventID)
                )
            }
            return LocalEventClassificationInput(
                rootPath: registration.rootPath.path,
                participant: registration.participant,
                observesContinuity: registration.observationIdentity != nil,
                scopes: registration.observationScopes
            )
        }
        if registrationWasReplaced {
            continuityLedger.markUncertain(registrationId: worktreeId)
        }
        guard let classificationInput else { return }

        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: rawEvents,
            ordinaryPaths: ordinaryPaths,
            rootPath: classificationInput.rootPath,
            observationScopes: classificationInput.scopes
        )

        var registrationChangedDuringClassification = false
        lifecycleLock.withLock {
            guard !hasShutdown, !hasStoppedActivityAdmission,
                let registration = streamByWorktreeId[worktreeId]
            else { return }
            guard registration.lifecycleGeneration == lifecycleGeneration else {
                registrationChangedDuringClassification = true
                return
            }
            if classificationInput.observesContinuity {
                continuityLedger.recordRawEvents(
                    registrationId: worktreeId,
                    events: classification.rawEvents
                )
            }
            ingressBuffer.yield(
                FSEventBatch(
                    worktreeId: worktreeId,
                    paths: classification.ordinaryPaths,
                    participant: classificationInput.participant,
                    observations: Self.observations(rawEvents: rawEvents)
                )
            )
        }
        if registrationChangedDuringClassification {
            continuityLedger.markUncertain(registrationId: worktreeId)
        }
    }

    private func retainedRegistration(worktreeId: UUID) -> StreamRegistration? {
        lifecycleLock.withLock {
            guard !hasShutdown else { return nil }
            return streamByWorktreeId[worktreeId]
        }
    }

    private func retainCompositeStreams(
        worktreeId: UUID,
        observationIdentity: AgentStudioGit.GitStatusObservationIdentity,
        requiresSharedBinding: Bool?
    ) -> CompositeStreamRetention? {
        guard let registration = retainedRegistration(worktreeId: worktreeId) else { return nil }
        guard registration.observationIdentity == observationIdentity else {
            return nil
        }

        switch sharedExactItemObserverRegistry.retainBinding(
            worktreeId: worktreeId,
            bindingGeneration: registration.lifecycleGeneration
        ) {
        case .localOnly:
            guard requiresSharedBinding != true else {
                return nil
            }
            return CompositeStreamRetention(
                registration: registration,
                sharedBindingLease: nil
            )
        case .shared(let sharedBindingLease):
            guard requiresSharedBinding != false else {
                return nil
            }
            return CompositeStreamRetention(
                registration: registration,
                sharedBindingLease: sharedBindingLease
            )
        case .invalid:
            return nil
        }
    }

    private func installSharedBinding(
        worktreeId: UUID,
        registration: StreamRegistration,
        exactItemsByParent: [DarwinSharedExactItemParentKey: Set<String>]
    ) -> Bool {
        let lifecycleGeneration = registration.lifecycleGeneration
        guard
            sharedExactItemObserverRegistry.bind(
                worktreeId: worktreeId,
                bindingGeneration: lifecycleGeneration,
                observationIdentity: registration.observationIdentity,
                exactItemsByParent: exactItemsByParent,
                bindingIsCurrent: { [weak self] in
                    self?.registrationIsCurrent(
                        worktreeId: worktreeId,
                        lifecycleGeneration: lifecycleGeneration
                    ) == true
                }
            )
        else {
            continuityLedger.unregister(registrationId: worktreeId)
            return false
        }
        guard
            registrationIsCurrent(
                worktreeId: worktreeId,
                lifecycleGeneration: lifecycleGeneration
            )
        else {
            sharedExactItemObserverRegistry.unbind(
                worktreeId: worktreeId,
                bindingGeneration: lifecycleGeneration
            )
            continuityLedger.unregister(registrationId: worktreeId)
            return false
        }
        return true
    }

    private func flush(_ streamRetention: CompositeStreamRetention) -> Bool {
        // Flushes may synchronously wait for callback queues. The registration
        // and shared leases were retained under their owners' locks, but no
        // lifecycle or registry lock remains held while either flush executes.
        guard streamRetention.registration.streamLifetime.flush() else { return false }
        return streamRetention.sharedBindingLease?.flush() ?? true
    }

    private func compositeStreamsAreCurrent(
        worktreeId: UUID,
        streamRetention: CompositeStreamRetention
    ) -> Bool {
        guard
            registrationMatches(
                worktreeId: worktreeId,
                lifecycleGeneration: streamRetention.registration.lifecycleGeneration,
                observationIdentity: streamRetention.registration.observationIdentity
            )
        else {
            return false
        }
        if let sharedBindingLease = streamRetention.sharedBindingLease {
            return sharedExactItemObserverRegistry.bindingIsCurrent(
                worktreeId: worktreeId,
                lease: sharedBindingLease
            )
        }
        return sharedExactItemObserverRegistry.hasNoSharedBinding(worktreeId: worktreeId)
    }

    private func registrationIsCurrent(
        worktreeId: UUID,
        lifecycleGeneration: UInt64
    ) -> Bool {
        lifecycleLock.withLock {
            !hasShutdown
                && streamByWorktreeId[worktreeId]?.lifecycleGeneration == lifecycleGeneration
        }
    }

    private func registrationMatches(
        worktreeId: UUID,
        lifecycleGeneration: UInt64,
        observationIdentity: AgentStudioGit.GitStatusObservationIdentity?
    ) -> Bool {
        lifecycleLock.withLock {
            guard !hasShutdown, let registration = streamByWorktreeId[worktreeId] else {
                return false
            }
            return registration.lifecycleGeneration == lifecycleGeneration
                && registration.observationIdentity == observationIdentity
        }
    }

    private func retireRegistrationAfterRootChange(
        worktreeId: UUID,
        lifecycleGeneration: UInt64,
        rawEvents: [(path: String, eventId: FSEventStreamEventId, flags: FSEventStreamEventFlags)],
        ordinaryPaths: [String]
    ) {
        let retiredRegistration = lifecycleLock.withLock { () -> StreamRegistration? in
            guard !hasShutdown,
                let registration = streamByWorktreeId[worktreeId],
                registration.lifecycleGeneration == lifecycleGeneration
            else {
                return nil
            }
            streamByWorktreeId.removeValue(forKey: worktreeId)
            return registration
        }
        guard let retiredRegistration else { return }

        continuityLedger.unregister(registrationId: worktreeId)
        sharedExactItemObserverRegistry.unbind(
            worktreeId: worktreeId,
            bindingGeneration: lifecycleGeneration
        )

        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: rawEvents,
            ordinaryPaths: ordinaryPaths,
            rootPath: retiredRegistration.rootPath.path,
            observationScopes: retiredRegistration.observationScopes
        )
        ingressBuffer.yield(
            FSEventBatch(
                worktreeId: worktreeId,
                paths: classification.ordinaryPaths,
                participant: retiredRegistration.participant,
                observations: Self.observations(rawEvents: rawEvents),
                requiresFullGitRefresh: true
            )
        )
        Self.scheduleTeardown(retiredRegistration)
    }

    private func allocateLifecycleGeneration() -> UInt64 {
        lifecycleLock.withLock {
            nextLifecycleGeneration &+= 1
            return nextLifecycleGeneration
        }
    }
}

extension DarwinFSEventStreamClient {
    private static func observations(
        rawEvents: [(path: String, eventId: FSEventStreamEventId, flags: FSEventStreamEventFlags)]
    ) -> [FSEventObservation] {
        rawEvents.map { event in
            FSEventObservation(
                path: event.path,
                eventID: UInt64(event.eventId),
                flags: UInt32(event.flags)
            )
        }
    }

    private static func teardown(_ registration: StreamRegistration) {
        registration.streamLifetime.retire()
    }

    private static func scheduleTeardown(_ registration: StreamRegistration) {
        registration.streamLifetime.scheduleRetirement()
    }
}

extension DarwinFSEventStreamClient {
    @concurrent
    nonisolated package func captureActivityBarrier() async -> FSEventActivityBarrier? {
        let registrations = lifecycleLock.withLock { () -> [(UUID, StreamRegistration)]? in
            guard !hasShutdown else { return nil }
            return streamByWorktreeId.sorted { $0.key.uuidString < $1.key.uuidString }
        }
        guard let registrations else { return nil }

        for (_, registration) in registrations {
            guard registration.streamLifetime.flush() else { return nil }
        }
        guard
            let sharedBarrierSnapshot =
                sharedExactItemObserverRegistry
                .captureActivityBarrierSnapshot()
        else {
            return nil
        }
        let sharedBarrier = sharedBarrierSnapshot.barrier

        let localBarrier = lifecycleLock.withLock { () -> FSEventActivityBarrier? in
            guard !hasShutdown else { return nil }
            var bindings: [FSEventParticipantBinding] = []
            var deliveredEventIDByParticipant: [FSEventParticipant: UInt64] = [:]
            for (worktreeId, retainedRegistration) in registrations {
                guard
                    let currentRegistration = streamByWorktreeId[worktreeId],
                    currentRegistration.lifecycleGeneration == retainedRegistration.lifecycleGeneration
                else { return nil }
                let deliveredEventID =
                    latestEventIDByParticipant[retainedRegistration.participant]
                    ?? 0
                bindings.append(
                    FSEventParticipantBinding(
                        worktreeId: worktreeId,
                        participant: retainedRegistration.participant
                    )
                )
                deliveredEventIDByParticipant[retainedRegistration.participant] = deliveredEventID
            }
            return FSEventActivityBarrier(
                bindings: bindings,
                deliveredEventIDByParticipant: deliveredEventIDByParticipant
            )
        }
        guard let localBarrier else { return nil }
        let barrier = FSEventActivityBarrier(
            bindings: (localBarrier.bindings + sharedBarrier.bindings).sorted {
                if $0.participant.scopeKey != $1.participant.scopeKey {
                    return $0.participant.scopeKey < $1.participant.scopeKey
                }
                return $0.worktreeId.uuidString < $1.worktreeId.uuidString
            },
            deliveredEventIDByParticipant: localBarrier.deliveredEventIDByParticipant.merging(
                sharedBarrier.deliveredEventIDByParticipant,
                uniquingKeysWith: max
            )
        )
        guard await ingressBuffer.enqueueActivityProcessingFence() else { return nil }
        guard localActivityBarrierIsCurrent(registrations: registrations),
            sharedExactItemObserverRegistry.activityBarrierIsCurrent(sharedBarrierSnapshot)
        else {
            return nil
        }
        return barrier
    }

    private func localActivityBarrierIsCurrent(
        registrations: [(UUID, StreamRegistration)]
    ) -> Bool {
        lifecycleLock.withLock {
            guard !hasShutdown, streamByWorktreeId.count == registrations.count else {
                return false
            }
            return registrations.allSatisfy { worktreeId, capturedRegistration in
                streamByWorktreeId[worktreeId]?.lifecycleGeneration
                    == capturedRegistration.lifecycleGeneration
            }
        }
    }
}
