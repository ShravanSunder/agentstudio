import Foundation

/// Per-runtime replay buffer for `RuntimeEnvelope` with bounded memory and TTL eviction.
///
/// Uses a ring buffer to preserve append order and supports gap-aware replay queries
/// via `eventsSince(seq:)`.
@MainActor
final class EventReplayBuffer {
    struct Config: Sendable {
        let maxEvents: Int
        let maxBytes: Int
        let ttl: Duration

        init(maxEvents: Int = 1000, maxBytes: Int = 1_048_576, ttl: Duration = .seconds(300)) {
            self.maxEvents = max(1, maxEvents)
            self.maxBytes = max(1, maxBytes)
            self.ttl = ttl
        }
    }

    struct ReplayResult: Sendable {
        let events: [RuntimeEnvelope]
        let nextSeq: UInt64
        let gapDetected: Bool
    }

    struct BufferStats: Sendable, Equatable {
        let eventCount: Int
        let estimatedBytes: Int
        let oldestSeq: UInt64?
        let newestSeq: UInt64?
    }

    private struct Entry {
        let envelope: RuntimeEnvelope
        let estimatedBytes: Int
    }

    private let config: Config
    private let clock: ContinuousClock

    private var ring: [Entry?]
    private var head: Int = 0
    private var countValue: Int = 0
    private var estimatedBytesValue: Int = 0

    init(config: Config = Config(), clock: ContinuousClock = ContinuousClock()) {
        self.config = config
        self.clock = clock
        self.ring = Array(repeating: nil, count: config.maxEvents)
    }

    /// Compatibility initializer for older call sites/tests that only set capacity.
    convenience init(capacity: Int = 200) {
        self.init(
            config: Config(
                maxEvents: max(1, capacity),
                maxBytes: Int.max / 4,
                ttl: .seconds(315_576_000)  // ~10 years
            )
        )
    }

    func append(_ envelope: RuntimeEnvelope) {
        evictStale(now: clock.now)

        let envelopeSize = Self.estimateSize(envelope)
        while countValue >= config.maxEvents || estimatedBytesValue + envelopeSize > config.maxBytes, countValue > 0 {
            evictOldest()
        }

        let entry = Entry(envelope: envelope, estimatedBytes: envelopeSize)
        ring[head] = entry
        head = (head + 1) % ring.count
        countValue += 1
        estimatedBytesValue += envelopeSize
    }

    var count: Int {
        countValue
    }

    func events() -> [RuntimeEnvelope] {
        evictStale(now: clock.now)
        return orderedEntries().map(\.envelope)
    }

    func eventsSince(seq: UInt64) -> ReplayResult {
        evictStale(now: clock.now)
        let ordered = orderedEntries().map(\.envelope)
        guard let oldest = ordered.first?.seq else {
            return ReplayResult(events: [], nextSeq: seq, gapDetected: false)
        }

        let nextExpected = seq == .max ? .max : seq + 1
        let gapDetected = nextExpected < oldest

        let replayEvents = ordered.filter { $0.seq > seq }
        let nextSeq = replayEvents.last?.seq ?? seq
        return ReplayResult(events: replayEvents, nextSeq: nextSeq, gapDetected: gapDetected)
    }

    func evictStale(now: ContinuousClock.Instant) {
        while let oldestEntry = oldestEntry(), oldestEntry.envelope.timestamp.duration(to: now) > config.ttl {
            evictOldest()
        }
    }

    var stats: BufferStats {
        evictStale(now: clock.now)
        let ordered = orderedEntries().map(\.envelope)
        return BufferStats(
            eventCount: countValue,
            estimatedBytes: estimatedBytesValue,
            oldestSeq: ordered.first?.seq,
            newestSeq: ordered.last?.seq
        )
    }

    private func oldestEntry() -> Entry? {
        guard countValue > 0 else { return nil }
        return ring[tailIndex]
    }

    private var tailIndex: Int {
        (head - countValue + ring.count) % ring.count
    }

    private func evictOldest() {
        guard countValue > 0 else { return }

        let index = tailIndex
        if let entry = ring[index] {
            estimatedBytesValue = max(0, estimatedBytesValue - entry.estimatedBytes)
        }
        ring[index] = nil
        countValue -= 1

        if countValue == 0 {
            head = 0
            estimatedBytesValue = 0
        }
    }

    private func orderedEntries() -> [Entry] {
        guard countValue > 0 else { return [] }
        var entries: [Entry] = []
        entries.reserveCapacity(countValue)

        let start = tailIndex
        for offset in 0..<countValue {
            let index = (start + offset) % ring.count
            if let entry = ring[index] {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func estimateSize(_ envelope: RuntimeEnvelope) -> Int {
        var bytes = 128
        bytes += envelope.source.description.utf8.count

        switch envelope {
        case .pane(let paneEnvelope):
            bytes += paneEnvelope.commandId == nil ? 0 : 16
            bytes += paneEnvelope.correlationId == nil ? 0 : 16
            bytes += paneEnvelope.causationId == nil ? 0 : 16
            bytes += String(describing: paneEnvelope.paneKind).utf8.count
            bytes += estimateSize(of: paneEnvelope.event)
        case .worktree(let worktreeEnvelope):
            bytes += worktreeEnvelope.commandId == nil ? 0 : 16
            bytes += worktreeEnvelope.correlationId == nil ? 0 : 16
            bytes += worktreeEnvelope.causationId == nil ? 0 : 16
            bytes += 32
            bytes += estimateSize(of: worktreeEnvelope.event)
        case .system(let systemEnvelope):
            bytes += systemEnvelope.commandId == nil ? 0 : 16
            bytes += systemEnvelope.correlationId == nil ? 0 : 16
            bytes += systemEnvelope.causationId == nil ? 0 : 16
            bytes += estimateSize(of: systemEnvelope.event)
        }

        return bytes
    }

    private static func estimateSize(of event: PaneRuntimeEvent) -> Int {
        switch event {
        case .lifecycle:
            return 24
        case .terminal(let terminalEvent):
            return estimateSize(of: terminalEvent)
        case .browser(let browserEvent):
            return estimateSize(of: browserEvent)
        case .diff(let diffEvent):
            return estimateSize(of: diffEvent)
        case .editor(let editorEvent):
            return estimateSize(of: editorEvent)
        case .plugin(_, let event):
            return 24 + event.eventName.rawValue.utf8.count
        case .filesystem(let filesystemEvent):
            return estimateSize(of: filesystemEvent)
        case .artifact(let artifactEvent):
            return estimateSize(of: artifactEvent)
        case .security(let securityEvent):
            return estimateSize(of: securityEvent)
        case .error(let errorEvent):
            return 24 + String(describing: errorEvent).utf8.count
        }
    }

    private static func estimateSize(of event: WorktreeScopedEvent) -> Int {
        switch event {
        case .filesystem(let filesystemEvent):
            return estimateSize(of: filesystemEvent)
        case .gitWorkingDirectory(let gitEvent):
            return estimateSize(of: gitEvent)
        case .forge(let forgeEvent):
            return estimateSize(of: forgeEvent)
        case .security(let securityEvent):
            return estimateSize(of: securityEvent)
        }
    }

    private static func estimateSize(of event: SystemScopedEvent) -> Int {
        switch event {
        case .topology(let topologyEvent):
            return estimateSize(of: topologyEvent)
        case .appLifecycle:
            return 24
        case .focusChanged:
            return 24
        case .configChanged(let configEvent):
            switch configEvent {
            case .watchedPathsUpdated(let paths):
                return 24
                    + paths.reduce(into: 0) { partial, path in
                        partial += path.path.utf8.count
                    }
            case .workspacePersistenceUpdated:
                return 24
            }
        }
    }

    private static func estimateSize(of event: TopologyEvent) -> Int {
        switch event {
        case .repoDiscovered(let repoPath, let parentPath):
            return 24 + repoPath.path.utf8.count + parentPath.path.utf8.count
        case .repoRemoved(let repoPath):
            return 24 + repoPath.path.utf8.count
        case .worktreeRegistered(_, _, let rootPath):
            return 24 + rootPath.path.utf8.count
        case .worktreeUnregistered:
            return 24
        }
    }

    private static func estimateSize(of event: GitWorkingDirectoryEvent) -> Int {
        switch event {
        case .snapshotChanged(let snapshot):
            return 56 + snapshot.rootPath.path.utf8.count + (snapshot.branch?.utf8.count ?? 0)
        case .branchChanged(_, _, let from, let to):
            return 24 + from.utf8.count + to.utf8.count
        case .originChanged(_, let from, let to):
            return 24 + from.utf8.count + to.utf8.count
        case .worktreeDiscovered(_, let worktreePath, let branch, _):
            return 24 + worktreePath.path.utf8.count + branch.utf8.count
        case .worktreeRemoved(_, let worktreePath):
            return 24 + worktreePath.path.utf8.count
        case .diffAvailable:
            return 24
        }
    }

    private static func estimateSize(of event: ForgeEvent) -> Int {
        switch event {
        case .pullRequestCountsChanged(_, let countsByBranch):
            return 24
                + countsByBranch.keys.reduce(into: 0) { partial, key in
                    partial += key.utf8.count
                }
        case .checksUpdated:
            return 32
        case .refreshFailed(_, let error):
            return 24 + error.utf8.count
        case .rateLimited:
            return 24
        }
    }

    private static func estimateSize(of event: GhosttyEvent) -> Int {
        switch event {
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom:
            return 24
        case .titleChanged(let title):
            return 32 + title.utf8.count
        case .cwdChanged(let cwd):
            return 32 + cwd.utf8.count
        case .commandFinished:
            return 48
        case .bellRang:
            return 24
        case .scrollbarChanged:
            return 40
        case .unhandled:
            return 24
        }
    }

    private static func estimateSize(of event: BrowserEvent) -> Int {
        switch event {
        case .navigationCompleted(let url, _):
            return 48 + url.absoluteString.utf8.count
        case .pageLoaded(let url):
            return 32 + url.absoluteString.utf8.count
        case .consoleMessage(_, let message):
            return 32 + message.utf8.count
        }
    }

    private static func estimateSize(of event: DiffEvent) -> Int {
        switch event {
        case .diffLoaded:
            return 40
        case .hunkApproved(let hunkId):
            return 24 + hunkId.utf8.count
        case .allApproved:
            return 24
        }
    }

    private static func estimateSize(of event: EditorEvent) -> Int {
        switch event {
        case .contentSaved(let path):
            return 24 + path.utf8.count
        case .fileOpened(let path, let language):
            return 32 + path.utf8.count + (language?.utf8.count ?? 0)
        case .diagnosticsUpdated(let path, _, _):
            return 40 + path.utf8.count
        }
    }

    private static func estimateSize(of event: FilesystemEvent) -> Int {
        switch event {
        case .worktreeRegistered(_, _, let rootPath):
            return 40 + rootPath.path.utf8.count
        case .worktreeUnregistered:
            return 24
        case .filesChanged(let changeset):
            return 48 + changeset.paths.reduce(0) { partial, path in partial + path.utf8.count }
        case .gitSnapshotChanged(let snapshot):
            return 56 + snapshot.rootPath.path.utf8.count + (snapshot.branch?.utf8.count ?? 0)
        case .diffAvailable:
            return 32
        case .branchChanged(_, _, let from, let to):
            return 24 + from.utf8.count + to.utf8.count
        }
    }

    private static func estimateSize(of event: ArtifactEvent) -> Int {
        switch event {
        case .diffProduced(_, let artifact):
            return 64 + artifact.patchData.count
        case .approvalRequested(let request):
            return 32 + request.summary.utf8.count
        case .approvalDecided:
            return 32
        }
    }

    private static func estimateSize(of event: SecurityEvent) -> Int {
        switch event {
        case .networkEgressBlocked(let destination, let rule):
            return 24 + destination.utf8.count + rule.utf8.count
        case .filesystemAccessDenied(let path, let operation):
            return 24 + path.utf8.count + operation.utf8.count
        case .secretAccessed(let secretId, let consumerId):
            return 24 + secretId.utf8.count + consumerId.utf8.count
        case .processSpawnBlocked(let command, let rule):
            return 24 + command.utf8.count + rule.utf8.count
        case .sandboxStarted:
            return 48
        case .sandboxStopped(let reason):
            return 24 + reason.utf8.count
        case .sandboxHealthChanged:
            return 24
        }
    }
}
