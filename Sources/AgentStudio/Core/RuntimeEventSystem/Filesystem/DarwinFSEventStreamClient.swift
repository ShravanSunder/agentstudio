import AgentStudioGit
import AgentStudioInfrastructure
import CoreServices
import Foundation

package final class DarwinFSEventIngressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let eventsStream: AsyncStream<FSEventBatch>
    private let eventsContinuation: AsyncStream<FSEventBatch>.Continuation
    private let maximumRetainedOverflowPathsPerRegistration: Int
    private let overflowHandler: @Sendable (UUID) -> Void
    private let performanceAccumulator: DarwinFSEventIngressPerformanceAccumulator
    private var overflowRecoveryByWorktreeId: [UUID: FSEventOverflowRecovery] = [:]

    package init(
        capacity: Int,
        maximumRetainedOverflowPathsPerRegistration: Int =
            AppPolicies.FilesystemIngress.maximumRetainedOverflowPathsPerRegistration,
        performanceAccumulator: DarwinFSEventIngressPerformanceAccumulator =
            DarwinFSEventIngressPerformanceAccumulator(),
        overflowHandler: @escaping @Sendable (UUID) -> Void = { _ in }
    ) {
        precondition(capacity > 0)
        precondition(maximumRetainedOverflowPathsPerRegistration > 0)
        let (stream, continuation) = AsyncStream.makeStream(
            of: FSEventBatch.self,
            bufferingPolicy: .bufferingOldest(capacity)
        )
        eventsStream = stream
        eventsContinuation = continuation
        self.maximumRetainedOverflowPathsPerRegistration =
            maximumRetainedOverflowPathsPerRegistration
        self.performanceAccumulator = performanceAccumulator
        self.overflowHandler = overflowHandler
    }

    package func events() -> AsyncStream<FSEventBatch> {
        eventsStream
    }

    package func yield(
        _ batch: FSEventBatch,
        source: DarwinFSEventIngressSource = .local
    ) {
        lock.withLock {
            switch eventsContinuation.yield(batch) {
            case .enqueued:
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .accepted,
                    pathCount: batch.paths.count
                )
            case .dropped(let droppedBatch):
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .dropped,
                    pathCount: droppedBatch.paths.count
                )
                retainOverflowRecovery(droppedBatch)
                overflowHandler(droppedBatch.worktreeId)
            case .terminated:
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .terminated,
                    pathCount: batch.paths.count
                )
            @unknown default:
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .dropped,
                    pathCount: batch.paths.count
                )
                retainOverflowRecovery(batch)
                overflowHandler(batch.worktreeId)
            }
        }
    }

    package func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] {
        lock.withLock {
            defer { overflowRecoveryByWorktreeId.removeAll(keepingCapacity: true) }
            let recoveries = overflowRecoveryByWorktreeId.values.sorted {
                $0.worktreeId.uuidString < $1.worktreeId.uuidString
            }
            performanceAccumulator.recordOverflowDrain(
                recoveryCount: recoveries.count,
                retainedPathCount: recoveries.reduce(0) { $0 + ($1.paths?.count ?? 0) },
                coarseRecoveryCount: recoveries.count(where: { $0.paths == nil })
            )
            return recoveries
        }
    }

    private func retainOverflowRecovery(_ batch: FSEventBatch) {
        let batchContainsGitTopologyPath = batch.paths.contains(where: Self.isGitTopologyPath)
        if let existing = overflowRecoveryByWorktreeId[batch.worktreeId], existing.paths == nil {
            overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
                worktreeId: batch.worktreeId,
                paths: nil,
                containsGitTopologyPath: existing.containsGitTopologyPath
                    || batchContainsGitTopologyPath,
                requiresFullGitRefresh: existing.requiresFullGitRefresh
                    || batch.requiresFullGitRefresh
            )
            return
        }
        let existing = overflowRecoveryByWorktreeId[batch.worktreeId]
        var retainedPaths = existing?.paths ?? Set<String>()
        let containsGitTopologyPath =
            existing?.containsGitTopologyPath == true
            || batchContainsGitTopologyPath
        let requiresFullGitRefresh =
            existing?.requiresFullGitRefresh == true
            || batch.requiresFullGitRefresh
        for path in batch.paths {
            if retainedPaths.count >= maximumRetainedOverflowPathsPerRegistration,
                !retainedPaths.contains(path)
            {
                overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
                    worktreeId: batch.worktreeId,
                    paths: nil,
                    containsGitTopologyPath: containsGitTopologyPath,
                    requiresFullGitRefresh: requiresFullGitRefresh
                )
                return
            }
            retainedPaths.insert(path)
        }
        overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
            worktreeId: batch.worktreeId,
            paths: retainedPaths,
            containsGitTopologyPath: containsGitTopologyPath,
            requiresFullGitRefresh: requiresFullGitRefresh
        )
    }

    private static func isGitTopologyPath(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git")
    }

    package func finish() {
        eventsContinuation.finish()
    }
}

/// Production filesystem event client wiring point.
package final class DarwinFSEventStreamClient: FSEventStreamClient, GitCleanContinuityWitness,
    @unchecked Sendable
{
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
        let rootPath: URL
        let observationIdentity: AgentStudioGit.GitStatusObservationIdentity?
        let observationScopes: [AgentStudioGit.GitStatusObservationScope]
        let watchedPaths: [String]
        let stream: FSEventStreamRef
        let queue: DispatchQueue
        let callbackContextPtr: UnsafeMutableRawPointer
    }

    private struct CompositeStreamRetention {
        let registration: StreamRegistration
        let sharedBindingLease: DarwinSharedExactItemBindingLease?
    }

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

    private let lifecycleLock = NSLock()
    private var hasShutdown = false
    private var nextLifecycleGeneration: UInt64 = 0
    private var streamByWorktreeId: [UUID: StreamRegistration] = [:]
    private let ingressBuffer: DarwinFSEventIngressBuffer
    private let continuityLedger: GitCleanContinuityLedger
    private let sharedExactItemObserverRegistry: DarwinSharedExactItemObserverRegistry
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
            performanceAccumulator: ingressPerformanceAccumulator,
            fingerprintReader: sharedExactItemFingerprintReader
        )
    }

    deinit {
        shutdown()
    }

    package func events() -> AsyncStream<FSEventBatch> {
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
        defer { FSEventStreamRelease(currentRegistration.stream) }

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
        defer { FSEventStreamRelease(streamRetention.registration.stream) }

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
        defer { FSEventStreamRelease(streamRetention.registration.stream) }
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
        defer { FSEventStreamRelease(streamRetention.registration.stream) }
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

        return StreamRegistration(
            lifecycleGeneration: lifecycleGeneration,
            rootPath: rootPath,
            observationIdentity: observationIdentity,
            observationScopes: observationScopes,
            watchedPaths: watchedPaths,
            stream: stream,
            queue: queue,
            callbackContextPtr: callbackContextPtr
        )
    }

    private func emitRawEvents(
        worktreeId: UUID,
        lifecycleGeneration: UInt64,
        rawEvents: [(path: String, eventId: FSEventStreamEventId, flags: FSEventStreamEventFlags)],
        ordinaryPaths: [String]
    ) {
        guard !rawEvents.isEmpty else { return }

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
            guard !hasShutdown, let registration = streamByWorktreeId[worktreeId] else {
                return Optional<
                    (rootPath: String, observesContinuity: Bool, scopes: [AgentStudioGit.GitStatusObservationScope])
                >.none
            }
            guard registration.lifecycleGeneration == lifecycleGeneration else {
                registrationWasReplaced = true
                return nil
            }
            return (
                rootPath: registration.rootPath.path,
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
            guard !hasShutdown, let registration = streamByWorktreeId[worktreeId] else { return }
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
            if !classification.ordinaryPaths.isEmpty {
                ingressBuffer.yield(
                    FSEventBatch(worktreeId: worktreeId, paths: classification.ordinaryPaths)
                )
            }
        }
        if registrationChangedDuringClassification {
            continuityLedger.markUncertain(registrationId: worktreeId)
        }
    }

    private func retainedRegistration(worktreeId: UUID) -> StreamRegistration? {
        lifecycleLock.withLock {
            guard !hasShutdown, let registration = streamByWorktreeId[worktreeId] else { return nil }
            FSEventStreamRetain(registration.stream)
            return registration
        }
    }

    private func retainCompositeStreams(
        worktreeId: UUID,
        observationIdentity: AgentStudioGit.GitStatusObservationIdentity,
        requiresSharedBinding: Bool?
    ) -> CompositeStreamRetention? {
        guard let registration = retainedRegistration(worktreeId: worktreeId) else { return nil }
        guard registration.observationIdentity == observationIdentity else {
            FSEventStreamRelease(registration.stream)
            return nil
        }

        switch sharedExactItemObserverRegistry.retainBinding(
            worktreeId: worktreeId,
            bindingGeneration: registration.lifecycleGeneration
        ) {
        case .localOnly:
            guard requiresSharedBinding != true else {
                FSEventStreamRelease(registration.stream)
                return nil
            }
            return CompositeStreamRetention(
                registration: registration,
                sharedBindingLease: nil
            )
        case .shared(let sharedBindingLease):
            guard requiresSharedBinding != false else {
                FSEventStreamRelease(registration.stream)
                return nil
            }
            return CompositeStreamRetention(
                registration: registration,
                sharedBindingLease: sharedBindingLease
            )
        case .invalid:
            FSEventStreamRelease(registration.stream)
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
        FSEventStreamFlushSync(streamRetention.registration.stream)
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

    private static func teardown(_ registration: StreamRegistration) {
        FSEventStreamStop(registration.stream)
        FSEventStreamInvalidate(registration.stream)
        FSEventStreamRelease(registration.stream)
        Unmanaged<CallbackContext>.fromOpaque(registration.callbackContextPtr).release()
        _ = registration.queue
    }

    private static func scheduleTeardown(_ registration: StreamRegistration) {
        registration.queue.async {
            teardown(registration)
        }
    }
}
