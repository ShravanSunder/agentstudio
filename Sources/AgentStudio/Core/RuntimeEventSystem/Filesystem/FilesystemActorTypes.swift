import Foundation

struct FilesystemActorSchedulingClock: Sendable {
    let now: @Sendable () -> Duration
    let sleep: @Sendable (Duration) async throws -> Void

    static func continuous() -> Self {
        let clock = ContinuousClock()
        let origin = clock.now
        return Self(
            now: { origin.duration(to: clock.now) },
            sleep: { duration in
                try await AsyncDelay.taskSleep.wait(duration)
            }
        )
    }

    static func make<C: Clock>(clock: C) -> Self where C.Duration == Duration, C: Sendable {
        let origin = clock.now
        let delay = AsyncDelay.clock(clock)
        return Self(
            now: { origin.duration(to: clock.now) },
            sleep: { duration in
                try await delay.wait(duration)
            }
        )
    }
}

struct FilesystemActorRootState: Sendable {
    let repoId: UUID
    let rootPath: URL
    let canonicalRootPath: String
    var isActiveInApp: Bool
    var nextBatchSeq: UInt64
    var pathFilter: FilesystemPathFilter
}

struct FilesystemActorPathFilterReloadState: Sendable {
    let rootPath: URL
    let task: Task<FilesystemPathFilter, Never>
}

struct FilesystemActorPendingWorktreeChanges: Sendable {
    var projectedPaths: Set<String> = []
    var containsGitInternalChanges = false
    var suppressedIgnoredPathCount = 0
    var suppressedGitInternalPathCount = 0
    var firstPendingTimestamp: Duration?
    var lastPendingTimestamp: Duration?

    var hasPendingChanges: Bool {
        !projectedPaths.isEmpty
            || containsGitInternalChanges
            || suppressedGitInternalPathCount > 0
    }

    mutating func recordPendingChange(at timestamp: Duration) {
        if firstPendingTimestamp == nil {
            firstPendingTimestamp = timestamp
        }
        lastPendingTimestamp = timestamp
    }
}

struct FilesystemActorWatchedFolderRefreshScanResult {
    let summary: WatchedFolderRefreshSummary
    let removedClonePaths: Set<URL>
}

struct FilesystemActorWatchedFolderRefreshResult {
    let repoPaths: [URL]
    let removedClonePaths: Set<URL>
}
