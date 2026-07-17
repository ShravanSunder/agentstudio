import Foundation

enum BridgeSharedFileSnapshotRowKind: String, Equatable, Sendable {
    case file
    case directory
    case symbolicLink
}

struct BridgeSharedFileSnapshotRow: Equatable, Sendable {
    let pathIdentity: String
    let parentPathIdentity: String?
    let kind: BridgeSharedFileSnapshotRowKind
    let byteCount: Int
    let statusIdentity: String?
    let isIgnored: Bool
}

struct BridgeSharedFileSnapshotWindow: Equatable, Sendable {
    let ordinal: Int
    let rows: [BridgeSharedFileSnapshotRow]
}

struct BridgeSharedFileSnapshotBuild: Equatable, Sendable {
    let orderedWindows: [BridgeSharedFileSnapshotWindow]
    let retainedByteCount: Int

    var orderedRows: [BridgeSharedFileSnapshotRow] {
        orderedWindows.flatMap(\.rows)
    }
}
