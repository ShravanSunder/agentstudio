import Foundation

struct BridgeWorktreeFreshnessEpoch: Hashable, Sendable {
    let rawValue: UInt64
}

enum BridgeWorktreeProductKind: String, Sendable {
    case file
    case review
}

enum BridgeWorktreeProductConstructionArtifact: Equatable, Sendable {
    case fileSnapshot(BridgeSharedFileSnapshotBuild)
    case reviewTemplate(BridgeSharedReviewPackageTemplate)

    var productKind: BridgeWorktreeProductKind {
        switch self {
        case .fileSnapshot:
            return .file
        case .reviewTemplate:
            return .review
        }
    }

    var retainedByteCount: Int {
        switch self {
        case .fileSnapshot(let snapshot):
            return snapshot.retainedByteCount
        case .reviewTemplate(let template):
            return template.retainedByteCount
        }
    }

    var contentLocatorCount: Int {
        switch self {
        case .fileSnapshot:
            return 0
        case .reviewTemplate(let template):
            return template.contentLocatorCount
        }
    }
}

struct BridgeWorktreeProductConstructionContext: Sendable {
    let key: BridgeWorktreeProductConstructionKey
    let epoch: BridgeWorktreeFreshnessEpoch
    let entryNonce: UInt64
}

struct BridgeWorktreeProductConstructionLease: Sendable {
    let key: BridgeWorktreeProductConstructionKey
    let epoch: BridgeWorktreeFreshnessEpoch
    let entryNonce: UInt64
    let leaseNonce: UInt64
    let artifact: BridgeWorktreeProductConstructionArtifact
}

enum BridgeWorktreeProductConstructionError: Error, Equatable, Sendable {
    case invalidated
    case artifactKindMismatch
}

enum BridgeWorktreeProductConstructionEventKind: String, Sendable {
    case buildStarted
    case consumerJoined
    case consumerCancelled
    case invalidated
    case buildReady
    case buildFailed
    case staleCompletionDropped
    case tombstoneCreated
    case leaseReleased
    case entryRemoved
}

struct BridgeWorktreeProductConstructionEvent: Sendable {
    let kind: BridgeWorktreeProductConstructionEventKind
    let productKind: BridgeWorktreeProductKind
    let epoch: BridgeWorktreeFreshnessEpoch
    let entryNonce: UInt64
    let leaseNonce: UInt64?
}

typealias BridgeWorktreeProductConstructionEventSink =
    @Sendable (
        BridgeWorktreeProductConstructionEvent
    ) -> Void

struct BridgeWorktreeProductConstructionSnapshot: Sendable {
    let entryCount: Int
    let waiterCount: Int
    let leaseCount: Int
    let payloadCount: Int
    let inFlightCount: Int
    let locatorCount: Int
    let drainingTombstoneCount: Int
    let retainedArtifactByteCount: Int
}
