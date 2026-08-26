import AgentStudioInfrastructure
import CoreServices
import Foundation

package final class DarwinFSEventIngressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let eventsStream: AsyncStream<FSEventBatch>
    private let eventsContinuation: AsyncStream<FSEventBatch>.Continuation
    private let maximumRetainedOverflowPathsPerRegistration: Int
    private var overflowRecoveryByWorktreeId: [UUID: FSEventOverflowRecovery] = [:]

    package init(
        capacity: Int,
        maximumRetainedOverflowPathsPerRegistration: Int =
            AppPolicies.FilesystemIngress.maximumRetainedOverflowPathsPerRegistration
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
            case .terminated:
                break
            @unknown default:
                retainOverflowRecovery(batch)
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
        if let existing = overflowRecoveryByWorktreeId[batch.worktreeId], existing.paths == nil {
            return
        }
        var retainedPaths = overflowRecoveryByWorktreeId[batch.worktreeId]?.paths ?? Set<String>()
        for path in batch.paths {
            if retainedPaths.count >= maximumRetainedOverflowPathsPerRegistration,
                !retainedPaths.contains(path)
            {
                overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
                    worktreeId: batch.worktreeId,
                    paths: nil
                )
                return
            }
            retainedPaths.insert(path)
        }
        overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
            worktreeId: batch.worktreeId,
            paths: retainedPaths
        )
    }

    package func finish() {
        eventsContinuation.finish()
    }
}

/// Production filesystem event client wiring point.
///
/// This implementation keeps lifecycle and registration semantics concrete and
/// deterministic at runtime while event ingestion remains routed through actor
/// seams (`enqueueRawPaths`) during this migration phase.
package final class DarwinFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private final class CallbackContext {
        weak var client: DarwinFSEventStreamClient?
        let worktreeId: UUID

        init(client: DarwinFSEventStreamClient, worktreeId: UUID) {
            self.client = client
            self.worktreeId = worktreeId
        }
    }

    private struct StreamRegistration {
        let rootPath: URL
        let stream: FSEventStreamRef
        let queue: DispatchQueue
        let callbackContextPtr: UnsafeMutableRawPointer
    }

    private static let callback: FSEventStreamCallback = { _, clientContextInfo, eventCount, eventPaths, _, _ in
        guard let clientContextInfo else { return }

        let context = Unmanaged<CallbackContext>.fromOpaque(clientContextInfo).takeUnretainedValue()
        guard let client = context.client else { return }

        let pathArray = unsafeBitCast(eventPaths, to: CFArray.self)
        let pathCount = CFArrayGetCount(pathArray)
        let boundedCount = min(Int(eventCount), pathCount)
        var changedPaths: [String] = []
        changedPaths.reserveCapacity(boundedCount)
        for index in 0..<boundedCount {
            let value = CFArrayGetValueAtIndex(pathArray, index)
            guard let value else { continue }
            let path = unsafeBitCast(value, to: CFString.self) as String
            changedPaths.append(path)
        }
        client.emitBatch(worktreeId: context.worktreeId, paths: changedPaths)
    }

    private static let defaultLatency: CFTimeInterval = 0.1

    private let lifecycleLock = NSLock()
    private var hasShutdown = false
    private var streamByWorktreeId: [UUID: StreamRegistration] = [:]
    private let ingressBuffer: DarwinFSEventIngressBuffer

    package init(
        bufferedFineBatchCapacity: Int = AppPolicies.FilesystemIngress.bufferedFineBatchCapacity
    ) {
        ingressBuffer = DarwinFSEventIngressBuffer(capacity: bufferedFineBatchCapacity)
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

        guard let registration = makeRegistration(worktreeId: worktreeId, rootPath: canonicalRootPath) else {
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
        ingressBuffer.finish()
    }

    private func makeRegistration(worktreeId: UUID, rootPath: URL) -> StreamRegistration? {
        let callbackContext = CallbackContext(client: self, worktreeId: worktreeId)
        let callbackContextPtr = Unmanaged.passRetained(callbackContext).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: callbackContextPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let watchPaths = [rootPath.path as NSString] as CFArray
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
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Unmanaged<CallbackContext>.fromOpaque(callbackContextPtr).release()
            return nil
        }

        return StreamRegistration(
            rootPath: rootPath,
            stream: stream,
            queue: queue,
            callbackContextPtr: callbackContextPtr
        )
    }

    private func emitBatch(worktreeId: UUID, paths: [String]) {
        guard !paths.isEmpty else { return }

        lifecycleLock.withLock {
            guard !hasShutdown, streamByWorktreeId[worktreeId] != nil else { return }
            ingressBuffer.yield(FSEventBatch(worktreeId: worktreeId, paths: paths))
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
