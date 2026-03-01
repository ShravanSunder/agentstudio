import Foundation

/// Production filesystem event client wiring point.
///
/// This implementation keeps lifecycle and registration semantics concrete and
/// deterministic at runtime while event ingestion remains routed through actor
/// seams (`enqueueRawPaths`) during this migration phase.
final class DarwinFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let lifecycleLock = NSLock()
    private var hasShutdown = false
    private var rootPathByWorktreeId: [UUID: URL] = [:]

    private let eventsStream: AsyncStream<FSEventBatch>
    private let eventsContinuation: AsyncStream<FSEventBatch>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: FSEventBatch.self)
        self.eventsStream = stream
        self.eventsContinuation = continuation
    }

    deinit {
        shutdown()
    }

    func events() -> AsyncStream<FSEventBatch> {
        eventsStream
    }

    func register(worktreeId: UUID, repoId _: UUID, rootPath: URL) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !hasShutdown else { return }
        rootPathByWorktreeId[worktreeId] = rootPath.standardizedFileURL.resolvingSymlinksInPath()
    }

    func unregister(worktreeId: UUID) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        rootPathByWorktreeId.removeValue(forKey: worktreeId)
    }

    func shutdown() {
        lifecycleLock.lock()
        if hasShutdown {
            lifecycleLock.unlock()
            return
        }
        hasShutdown = true
        rootPathByWorktreeId.removeAll(keepingCapacity: false)
        lifecycleLock.unlock()
        eventsContinuation.finish()
    }
}
