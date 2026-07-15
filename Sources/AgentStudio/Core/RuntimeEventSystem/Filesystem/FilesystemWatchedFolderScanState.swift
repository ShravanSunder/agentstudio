import Foundation

struct FilesystemWatchedFolderRegistration: Sendable {
    let watchedPath: WatchedPath
    let registeredRoot: RegisteredRootDescriptor
    let legacyCallbackRoutingID: UUID
}

struct FilesystemWatchedFolderInventory: Sendable {
    let repoGroups: [RepoScanner.RepoScanGroup]
}

struct FilesystemManualWatchedFolderRefreshWait: Sendable {
    let receiptsBySourceID: [FilesystemSourceID: WatchedFolderScanDemandReceipt]
    let continuation: CheckedContinuation<WatchedFolderRefreshSummary, Never>
}

enum FilesystemManualWatchedFolderRefreshState: Sendable {
    case idle
    case running(
        id: UUID,
        task: Task<WatchedFolderRefreshSummary, Never>
    )
    case waitingForResults(
        id: UUID,
        task: Task<WatchedFolderRefreshSummary, Never>,
        wait: FilesystemManualWatchedFolderRefreshWait
    )

    var task: Task<WatchedFolderRefreshSummary, Never>? {
        switch self {
        case .idle:
            nil
        case .running(_, let task), .waitingForResults(_, let task, _):
            task
        }
    }
}

enum FilesystemWatchedFolderResultDrainState: Sendable {
    case idle
    case bindingConsumer(id: UUID, task: Task<Void, Never>)
    case running(id: UUID, task: Task<Void, Never>)

    var task: Task<Void, Never>? {
        switch self {
        case .idle:
            nil
        case .bindingConsumer(_, let task), .running(_, let task):
            task
        }
    }
}

struct FilesystemWatchedFolderScanState: Sendable {
    let resultConsumer = WatchedFolderScanResultConsumerToken.make()
    var isShuttingDown = false
    var registrationsBySourceID: [FilesystemSourceID: FilesystemWatchedFolderRegistration] = [:]
    var sourceIDByLegacyCallbackRoutingID: [UUID: FilesystemSourceID] = [:]
    var inventoryBySourceID: [FilesystemSourceID: FilesystemWatchedFolderInventory] = [:]
    var latestDemandCoverageBySourceID: [FilesystemSourceID: WatchedFolderScanDemandCoverage] = [:]
    var appliedDemandCoverageBySourceID: [FilesystemSourceID: WatchedFolderScanDemandCoverage] = [:]
    var lastAppliedResultIDBySourceID: [FilesystemSourceID: WatchedFolderScanResultID] = [:]
    var nextRegistrationGenerationBySourceID: [FilesystemSourceID: UInt64] = [:]
    var manualRefreshState: FilesystemManualWatchedFolderRefreshState = .idle
    var resultDrainState: FilesystemWatchedFolderResultDrainState = .idle
    var fallbackTask: Task<Void, Never>?
}
