import AgentStudioGit
import AgentStudioInfrastructure
import CoreServices
import Darwin
import Foundation

package final class DarwinFSEventIngressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let eventsStream: AsyncStream<FSEventBatch>
    private let eventsContinuation: AsyncStream<FSEventBatch>.Continuation
    private let maximumRetainedOverflowPathsPerRegistration: Int
    private let overflowHandler: @Sendable (UUID) -> Void
    private var overflowRecoveryByWorktreeId: [UUID: FSEventOverflowRecovery] = [:]

    package init(
        capacity: Int,
        maximumRetainedOverflowPathsPerRegistration: Int =
            AppPolicies.FilesystemIngress.maximumRetainedOverflowPathsPerRegistration,
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
        self.overflowHandler = overflowHandler
    }

    package func events() -> AsyncStream<FSEventBatch> {
        eventsStream
    }

    package func yield(_ batch: FSEventBatch) {
        lock.withLock {
            switch eventsContinuation.yield(batch) {
            case .enqueued:
                break
            case .dropped(let droppedBatch):
                retainOverflowRecovery(droppedBatch)
                overflowHandler(droppedBatch.worktreeId)
            case .terminated:
                break
            @unknown default:
                retainOverflowRecovery(batch)
                overflowHandler(batch.worktreeId)
            }
        }
    }

    package func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] {
        lock.withLock {
            defer { overflowRecoveryByWorktreeId.removeAll(keepingCapacity: true) }
            return overflowRecoveryByWorktreeId.values.sorted {
                $0.worktreeId.uuidString < $1.worktreeId.uuidString
            }
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

package struct DarwinFSEventClassifiedRawEvent: Sendable {
    package let eventId: FSEventStreamEventId
    package let flags: FSEventStreamEventFlags
    package let hasRelevantMutation: Bool
}

package struct DarwinFSEventClassification: Sendable {
    package let rawEvents: [DarwinFSEventClassifiedRawEvent]
    package let ordinaryPaths: [String]
}

package enum DarwinFSEventPathClassifier {
    package static func classify(
        rawEvents: [(path: String, eventId: FSEventStreamEventId, flags: FSEventStreamEventFlags)],
        ordinaryPaths: [String],
        rootPath: String,
        observationScopes: [AgentStudioGit.GitStatusObservationScope],
        normalize: (String) -> String = DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath
    ) -> DarwinFSEventClassification {
        var normalizedPathByRawPath: [String: String] = [:]
        normalizedPathByRawPath.reserveCapacity(rawEvents.count)

        func normalizedPath(for rawPath: String) -> String {
            if let existing = normalizedPathByRawPath[rawPath] {
                return existing
            }
            let normalizedPath = normalize(rawPath)
            normalizedPathByRawPath[rawPath] = normalizedPath
            return normalizedPath
        }

        let canonicalScopes = observationScopes.map { scope in
            let path = scope.path.path
            return (
                kind: scope.kind,
                path: path,
                subtreePrefix: scope.kind == .subtree ? path + "/" : nil
            )
        }
        let rootPrefix = rootPath + "/"
        let classifiedRawEvents = rawEvents.map { event in
            let candidate = normalizedPath(for: event.path)
            let hasRelevantMutation = canonicalScopes.contains { scope in
                switch scope.kind {
                case .item:
                    return candidate == scope.path
                case .subtree:
                    return candidate == scope.path
                        || scope.subtreePrefix.map { candidate.hasPrefix($0) } == true
                }
            }
            return DarwinFSEventClassifiedRawEvent(
                eventId: event.eventId,
                flags: event.flags,
                hasRelevantMutation: hasRelevantMutation
            )
        }
        let ordinaryWorktreePaths = ordinaryPaths.filter { path in
            let candidate = normalizedPath(for: path)
            return candidate == rootPath || candidate.hasPrefix(rootPrefix)
        }
        return DarwinFSEventClassification(
            rawEvents: classifiedRawEvents,
            ordinaryPaths: ordinaryWorktreePaths
        )
    }

}

/// Production filesystem event client wiring point.
///
/// This implementation keeps lifecycle and registration semantics concrete and
/// deterministic at runtime while event ingestion remains routed through actor
/// seams (`enqueueRawPaths`) during this migration phase.
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

    package init(
        bufferedFineBatchCapacity: Int = AppPolicies.FilesystemIngress.bufferedFineBatchCapacity,
        sharedExactItemStreamFactory: @escaping DarwinSharedExactItemStreamFactory =
            DarwinSharedExactItemNativeStream.start
    ) {
        let continuityLedger = GitCleanContinuityLedger()
        let ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: bufferedFineBatchCapacity,
            overflowHandler: { worktreeId in
                continuityLedger.markUncertain(registrationId: worktreeId)
            }
        )
        self.continuityLedger = continuityLedger
        self.ingressBuffer = ingressBuffer
        sharedExactItemObserverRegistry = DarwinSharedExactItemObserverRegistry(
            streamFactory: sharedExactItemStreamFactory,
            recordRawEvents: { worktreeId, events in
                continuityLedger.recordRawEvents(
                    registrationId: worktreeId,
                    events: events
                )
            },
            markUncertain: { worktreeId in
                continuityLedger.markUncertain(registrationId: worktreeId)
            },
            yieldFullGitRefresh: { worktreeId in
                ingressBuffer.yield(
                    FSEventBatch(
                        worktreeId: worktreeId,
                        paths: [],
                        requiresFullGitRefresh: true
                    )
                )
            }
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

    package func register(worktreeId: UUID, repoId _: UUID, rootPath: URL) {
        let canonicalRootPath = Self.kernelCanonicalURL(rootPath)

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
        let canonicalRootPath = Self.kernelCanonicalURL(rootPath)
        guard let binding = bindingPlan(for: observationPlan) else { return nil }

        let currentRegistration = retainedRegistration(worktreeId: worktreeId)
        guard let currentRegistration, currentRegistration.rootPath == canonicalRootPath else { return nil }
        defer { FSEventStreamRelease(currentRegistration.stream) }

        continuityLedger.unregister(registrationId: worktreeId)
        let registration: StreamRegistration
        if currentRegistration.observationIdentity == observationPlan.identity,
            currentRegistration.watchedPaths == binding.localWatchedPaths,
            Self.scopesMatch(currentRegistration.observationScopes, binding.localScopes)
        {
            continuityLedger.register(
                registrationId: worktreeId,
                identity: observationPlan.identity
            )
            registration = currentRegistration
        } else {
            continuityLedger.unregister(registrationId: worktreeId)
            guard
                let replacement = makeRegistration(
                    worktreeId: worktreeId,
                    lifecycleGeneration: allocateLifecycleGeneration(),
                    rootPath: canonicalRootPath,
                    observationIdentity: observationPlan.identity,
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
            sharedExactItemObserverRegistry.bind(
                worktreeId: worktreeId,
                bindingGeneration: registration.lifecycleGeneration,
                exactItemsByParent: binding.sharedExactItemsByParent,
                bindingIsCurrent: { [weak self] in
                    self?.registrationIsCurrent(
                        worktreeId: worktreeId,
                        lifecycleGeneration: registration.lifecycleGeneration
                    ) == true
                }
            )
        else {
            continuityLedger.unregister(registrationId: worktreeId)
            return nil
        }
        guard
            registrationIsCurrent(
                worktreeId: worktreeId,
                lifecycleGeneration: registration.lifecycleGeneration
            )
        else {
            sharedExactItemObserverRegistry.unbind(
                worktreeId: worktreeId,
                bindingGeneration: registration.lifecycleGeneration
            )
            continuityLedger.unregister(registrationId: worktreeId)
            return nil
        }
        guard binding.sharedExactItemsByParent.isEmpty else {
            // S3 will compose local and shared stream barriers. Until then a
            // shared-dependent plan must never mint local-only authority.
            return nil
        }

        // A flush may synchronously wait for the callback queue. Never hold the
        // lifecycle lock while flushing because callbacks acquire that lock.
        FSEventStreamFlushSync(registration.stream)
        return continuityLedger.beginBarrier(
            registrationId: worktreeId,
            identity: observationPlan.identity
        )
    }

    @concurrent
    nonisolated package func commit(
        _ barrier: GitCleanContinuityBarrier
    ) async -> GitCleanContinuityAuthorityValidation {
        guard !sharedExactItemObserverRegistry.hasBinding(worktreeId: barrier.registrationId) else {
            return .requiresExact(.unsupportedObservation)
        }
        guard let registration = retainedRegistration(for: barrier) else {
            return .requiresExact(.registrationMissing)
        }
        defer { FSEventStreamRelease(registration.stream) }
        FSEventStreamFlushSync(registration.stream)
        return continuityLedger.commitBarrier(barrier)
    }

    @concurrent
    nonisolated package func renew(
        _ authority: GitCleanContinuityAuthority
    ) async -> GitCleanContinuityAuthorityValidation {
        guard !sharedExactItemObserverRegistry.hasBinding(worktreeId: authority.registrationId) else {
            return .requiresExact(.unsupportedObservation)
        }
        guard let registration = retainedRegistration(for: authority) else {
            return .requiresExact(.registrationMissing)
        }
        defer { FSEventStreamRelease(registration.stream) }
        FSEventStreamFlushSync(registration.stream)
        return continuityLedger.renew(authority)
    }

    package func retire(worktreeId: UUID, rootPath: URL) {
        let canonicalRootPath = Self.kernelCanonicalURL(rootPath)
        let matches = lifecycleLock.withLock {
            streamByWorktreeId[worktreeId]?.rootPath == canonicalRootPath
        }
        if matches {
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

    private func registrationIsCurrent(
        worktreeId: UUID,
        lifecycleGeneration: UInt64
    ) -> Bool {
        lifecycleLock.withLock {
            !hasShutdown
                && streamByWorktreeId[worktreeId]?.lifecycleGeneration == lifecycleGeneration
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

    private func retainedRegistration(for barrier: GitCleanContinuityBarrier) -> StreamRegistration? {
        lifecycleLock.withLock {
            guard !hasShutdown,
                let registration = streamByWorktreeId[barrier.registrationId],
                registration.observationIdentity == barrier.observationIdentity
            else {
                return nil
            }
            FSEventStreamRetain(registration.stream)
            return registration
        }
    }

    private func retainedRegistration(for authority: GitCleanContinuityAuthority) -> StreamRegistration? {
        lifecycleLock.withLock {
            guard !hasShutdown,
                let registration = streamByWorktreeId[authority.registrationId],
                registration.observationIdentity == authority.observationIdentity
            else {
                return nil
            }
            FSEventStreamRetain(registration.stream)
            return registration
        }
    }

    private func bindingPlan(
        for plan: AgentStudioGit.GitStatusObservationPlan
    ) -> DarwinFSEventBindingPlan? {
        guard !plan.scopes.isEmpty else { return nil }
        let scopes = plan.scopes.map { scope in
            AgentStudioGit.GitStatusObservationScope(
                kind: scope.kind,
                path: Self.kernelCanonicalURL(scope.path)
            )
        }
        guard let binding = DarwinFSEventBindingPlanner.plan(scopes: scopes) else { return nil }
        guard pathsShareVolume(binding.localWatchedPaths) else { return nil }
        return binding
    }

    private func pathsShareVolume(_ paths: [String]) -> Bool {
        let volumeNumbers = paths.compactMap { path -> NSNumber? in
            var candidate = URL(fileURLWithPath: path)
            while candidate.path != "/", !FileManager.default.fileExists(atPath: candidate.path) {
                candidate.deleteLastPathComponent()
            }
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: candidate.path)
            return attributes?[.systemNumber] as? NSNumber
        }
        return volumeNumbers.count == paths.count && Set(volumeNumbers).count == 1
    }

    private func allocateLifecycleGeneration() -> UInt64 {
        lifecycleLock.withLock {
            nextLifecycleGeneration &+= 1
            return nextLifecycleGeneration
        }
    }

    private static func scopesMatch(
        _ lhs: [AgentStudioGit.GitStatusObservationScope],
        _ rhs: [AgentStudioGit.GitStatusObservationScope]
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { lhsScope, rhsScope in
                lhsScope.kind == rhsScope.kind && lhsScope.path == rhsScope.path
            }
    }

    private static func kernelCanonicalURL(_ url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        var existingAncestor = standardizedURL
        var unresolvedComponents: [String] = []

        while true {
            if let resolvedPath = realPath(existingAncestor.path) {
                return unresolvedComponents.reversed().reduce(
                    URL(fileURLWithPath: resolvedPath)
                ) { resolvedURL, component in
                    resolvedURL.appending(path: component)
                }
            }
            guard existingAncestor.path != "/" else {
                return standardizedURL.resolvingSymlinksInPath()
            }
            unresolvedComponents.append(existingAncestor.lastPathComponent)
            existingAncestor.deleteLastPathComponent()
        }
    }

    private static func realPath(_ path: String) -> String? {
        path.withCString { pathPointer in
            guard let resolvedPointer = Darwin.realpath(pathPointer, nil) else { return nil }
            defer { free(resolvedPointer) }
            return String(cString: resolvedPointer)
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
