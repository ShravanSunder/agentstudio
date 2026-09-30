import Foundation
import GRDB

package enum CLIStoreChannel: String, Sendable {
    case stable
    case beta
    case debug
}

package struct CLIStoreIdentity: Equatable, Sendable {
    package let storeID: UUID
    package let channel: CLIStoreChannel
}

package enum CLIStoreFailure: Error, Equatable, Sendable {
    case unavailable
    case busy
    case superseded
    case channelMismatch
    case invalidIdentity
    case readOnly
}

package struct CLIStoreDecodeIssue: Equatable, Sendable {
    package enum Field: String, Sendable {
        case kind
        case paneID = "pane_id"
        case messageID = "message_id"
        case createdAt = "created_at"
    }

    package let rowID: Int64
    package let field: Field
}

package struct CLINoticeEntry: Equatable, Sendable {
    package let id: Int64
    package let paneID: UUID
    package let messageID: UUID
    package let payloadJSON: String
    package let createdAt: Date
}

package enum CLIOutboxEntry: Equatable, Sendable {
    case notice(CLINoticeEntry)

    package var id: Int64 {
        switch self {
        case .notice(let notice): notice.id
        }
    }
}

package struct CLIOutboxReadBatch: Equatable, Sendable {
    package let entries: [CLIOutboxEntry]
    /// Includes skipped rows so intake can disposition an undecodable prefix.
    package let lastReadID: Int64
}

/// Red-phase contract scaffold. S1 replaces the fail-open placeholders after
/// the Lead observes the new behavior tests failing.
package final class CLIStore: Sendable {
    let databaseQueue: DatabaseQueue
    package let identity: CLIStoreIdentity

    private init(databaseQueue: DatabaseQueue, identity: CLIStoreIdentity) {
        self.databaseQueue = databaseQueue
        self.identity = identity
    }

    package static func openWriter(
        url: URL,
        channel: CLIStoreChannel,
        logDecodeIssue: @escaping @Sendable (CLIStoreDecodeIssue) -> Void = { _ in }
    ) -> Result<CLIStore, CLIStoreFailure> {
        .failure(.unavailable)
    }

    package static func openReader(
        url: URL,
        expectedChannel: CLIStoreChannel,
        logDecodeIssue: @escaping @Sendable (CLIStoreDecodeIssue) -> Void = { _ in }
    ) -> Result<CLIStore, CLIStoreFailure> {
        .failure(.unavailable)
    }

    package func appendNotice(
        paneID: UUID,
        messageID: UUID,
        payloadJSON: String,
        createdAt: Date
    ) -> Result<CLIOutboxEntry, CLIStoreFailure> {
        .failure(.unavailable)
    }

    package func readOutbox(after lastHandledID: Int64) -> Result<CLIOutboxReadBatch, CLIStoreFailure> {
        .failure(.unavailable)
    }
}
