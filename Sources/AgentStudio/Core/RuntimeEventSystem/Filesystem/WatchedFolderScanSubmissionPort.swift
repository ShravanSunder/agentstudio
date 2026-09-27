import Foundation

/// How the FilesystemActor hands a scan request to the scheduler. Production submits
/// directly; tests substitute a port that holds the accepted result back from the actor,
/// so actor work interleaved with an in-flight submission can be ordered deterministically.
package struct WatchedFolderScanSubmissionPort: Sendable {
    let submit:
        @Sendable (
            WatchedFolderScanScheduler,
            WatchedFolderScanRequest,
            WatchedFolderScanSubmissionIntent
        ) async -> WatchedFolderScanSubmissionResult

    package static let direct = Self { scheduler, request, intent in
        await scheduler.submit(request, intent: intent)
    }
}
