import Foundation

struct BridgeSharedFileSnapshotPreparation: Sendable {
    let ignorePolicy: BridgeWorktreeFileIgnorePolicy
    let statusResult: GitWorkingTreeStatusResult
    let retainedByteCount: Int
}

struct BridgeSharedFileSnapshotWindow: Equatable, Sendable {
    let ordinal: Int
    let startIndex: Int
    let discoveredRowCount: Int
    let isFinalWindow: Bool
    let rows: [BridgeWorktreeTreeRowMetadata]
    let retainedByteCount: Int
}

struct BridgeSharedFileSnapshotCompletion: Equatable, Sendable {
    let retainedNonwindowByteCount: Int

    init(retainedNonwindowByteCount: Int = 0) {
        self.retainedNonwindowByteCount = retainedNonwindowByteCount
    }
}

struct BridgeSharedFileSnapshotBuild: Sendable {
    let preparation: BridgeSharedFileSnapshotPreparation
    let orderedWindows: [BridgeSharedFileSnapshotWindow]
    let retainedByteCount: Int

    init(
        preparation: BridgeSharedFileSnapshotPreparation,
        orderedWindows: [BridgeSharedFileSnapshotWindow],
        retainedByteCount: Int
    ) {
        self.preparation = preparation
        self.orderedWindows = orderedWindows
        self.retainedByteCount = retainedByteCount
    }

    var orderedRows: [BridgeWorktreeTreeRowMetadata] {
        orderedWindows.flatMap(\.rows)
    }
}
