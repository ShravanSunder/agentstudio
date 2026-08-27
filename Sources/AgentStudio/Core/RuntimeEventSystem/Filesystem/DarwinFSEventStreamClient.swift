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
                    || batchContainsGitTopologyPath
            )
            return
        }
        let existing = overflowRecoveryByWorktreeId[batch.worktreeId]
        var retainedPaths = existing?.paths ?? Set<String>()
        let containsGitTopologyPath =
            existing?.containsGitTopologyPath == true
            || batchContainsGitTopologyPath
        for path in batch.paths {
            if retainedPaths.count >= maximumRetainedOverflowPathsPerRegistration,
                !retainedPaths.contains(path)
            {
                overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
                    worktreeId: batch.worktreeId,
                    paths: nil,
                    containsGitTopologyPath: containsGitTopologyPath
                )
                return
            }
            retainedPaths.insert(path)
        }
        overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
            worktreeId: batch.worktreeId,
            paths: retainedPaths,
            containsGitTopologyPath: containsGitTopologyPath
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
        normalize: (String) -> String = lexicallyNormalizedAbsolutePath
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

    private static func lexicallyNormalizedAbsolutePath(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let requiresNormalization =
            path.contains("//")
            || path.contains("/./")
            || path.hasSuffix("/.")
            || path.contains("/../")
            || path.hasSuffix("/..")
        guard requiresNormalization else { return path }

        var normalizedComponents: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !normalizedComponents.isEmpty {
                    normalizedComponents.removeLast()
                }
            default:
                normalizedComponents.append(component)
            }
        }
        guard !normalizedComponents.isEmpty else { return "/" }
        return "/" + normalizedComponents.joined(separator: "/")
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

    private struct StreamRegistration {
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

    package init(
        bufferedFineBatchCapacity: Int = AppPolicies.FilesystemIngress.bufferedFineBatchCapacity
    ) {
        let continuityLedger = GitCleanContinuityLedger()
        self.continuityLedger = continuityLedger
        ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: bufferedFineBatchCapacity,
            overflowHandler: { worktreeId in
                continuityLedger.markUncertain(registrationId: worktreeId)
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
        let canonicalRootPath = rootPath.standardizedFileURL.resolvingSymlinksInPath()

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
        let registration: StreamRegistration?
        lifecycleLock.lock()
        registration = streamByWorktreeId.removeValue(forKey: worktreeId)
        lifecycleLock.unlock()

        if let registration {
            Self.teardown(registration)
        }
        continuityLedger.unregister(registrationId: worktreeId)
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
        ingressBuffer.finish()
    }

    @concurrent
    nonisolated package func prepare(
        worktreeId: UUID,
        rootPath: URL,
        observationPlan: AgentStudioGit.GitStatusObservationPlan
    ) async -> GitCleanContinuityBarrier? {
        guard observationPlan.support == .supported else { return nil }
        let canonicalRootPath = rootPath.standardizedFileURL.resolvingSymlinksInPath()
        guard let binding = bindingPaths(for: observationPlan) else { return nil }

        let currentRegistration = retainedRegistration(worktreeId: worktreeId)
        guard let currentRegistration, currentRegistration.rootPath == canonicalRootPath else { return nil }
        defer { FSEventStreamRelease(currentRegistration.stream) }

        let registration: StreamRegistration
        if currentRegistration.observationIdentity == observationPlan.identity,
            currentRegistration.watchedPaths == binding.watchedPaths
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
                    observationScopes: binding.scopes,
                    watchedPaths: binding.watchedPaths
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
        guard let registration = retainedRegistration(for: authority) else {
            return .requiresExact(.registrationMissing)
        }
        defer { FSEventStreamRelease(registration.stream) }
        FSEventStreamFlushSync(registration.stream)
        return continuityLedger.renew(authority)
    }

    package func retire(worktreeId: UUID, rootPath: URL) {
        let canonicalRootPath = rootPath.standardizedFileURL.resolvingSymlinksInPath()
        let matches = lifecycleLock.withLock {
            streamByWorktreeId[worktreeId]?.rootPath == canonicalRootPath
        }
        if matches {
            continuityLedger.unregister(registrationId: worktreeId)
        }
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
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )

        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.callback,
                &streamContext,
                watchPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.defaultLatency,
                flags
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

    private func bindingPaths(
        for plan: AgentStudioGit.GitStatusObservationPlan
    ) -> (scopes: [AgentStudioGit.GitStatusObservationScope], watchedPaths: [String])? {
        guard !plan.scopes.isEmpty else { return nil }
        let scopes = plan.scopes.map { scope in
            AgentStudioGit.GitStatusObservationScope(
                kind: scope.kind,
                path: scope.path.standardizedFileURL.resolvingSymlinksInPath()
            )
        }
        let watchedPaths = Set(
            scopes.map { scope in
                switch scope.kind {
                case .item:
                    scope.path.deletingLastPathComponent().path
                case .subtree:
                    scope.path.path
                }
            }
        ).sorted()
        guard !watchedPaths.isEmpty, pathsShareVolume(watchedPaths) else { return nil }
        return (scopes, watchedPaths)
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

    private static func teardown(_ registration: StreamRegistration) {
        FSEventStreamStop(registration.stream)
        FSEventStreamInvalidate(registration.stream)
        FSEventStreamRelease(registration.stream)
        Unmanaged<CallbackContext>.fromOpaque(registration.callbackContextPtr).release()
        _ = registration.queue
    }
}
