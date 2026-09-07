import Foundation

package struct WorkspaceUndoJournalTime: Sendable {
    package let utc: Date
    package let bootID: String
    package let uptimeNanoseconds: Int64

    package init(utc: Date, bootID: String, uptimeNanoseconds: Int64) {
        self.utc = utc
        self.bootID = bootID
        self.uptimeNanoseconds = uptimeNanoseconds
    }
}

package struct WorkspaceUndoCloseRecord: Sendable {
    package let closeID: UUID
    package let workspaceID: UUID
    package let sequence: Int64
    package let closedAt: Date
    package let expiresAt: Date
    package let deadlineBootID: String
    package let deadlineUptimeNanoseconds: Int64
    package let snapshot: WorkspaceUndoCloseSnapshot
}

package struct WorkspaceUndoCloseRetirement: Sendable {
    package let closeID: UUID
    package let members: [WorkspaceUndoCloseWrite.Member]
}

enum WorkspaceUndoJournalFailure: Error, Equatable {
    case invalidStoredIdentifier
    case unsupportedSnapshotVersion(Int)
    case snapshotMembershipMismatch
    case snapshotKindMismatch
    case invalidClock
    case deadlineOverflow
    case undoUnavailable
    case undoExpired
    case deadlineNeedsRecovery
    case restoreMembershipMismatch
}
