import AgentStudioCore
import Foundation
import Synchronization

package enum SessionStatusPublication: Sendable, Equatable {
    case set(AgentSessionStatus)
    case remove
}

/// The publication seam's RED shell; desired-value and retirement rules follow the gate.
package final class SessionStatusPublicationMailbox: Sendable {
    private let pending = Mutex<[PaneId: SessionStatusPublication]>([:])

    package init() {}

    @discardableResult
    package func offer(_ status: AgentSessionStatus, for paneId: PaneId) -> Bool {
        pending.withLock { $0[paneId] = .set(status) }
        return true
    }

    package func retire(_ paneId: PaneId) {
        pending.withLock { $0[paneId] = .remove }
    }

    package func takeBatch() -> [PaneId: SessionStatusPublication] {
        pending.withLock { batch in
            defer { batch.removeAll() }
            return batch
        }
    }
}

package actor SessionStatusPublicationLane {
    package nonisolated let mailbox: SessionStatusPublicationMailbox
    private let sink: @MainActor @Sendable ([PaneId: SessionStatusPublication]) async -> Void

    package init(
        mailbox: SessionStatusPublicationMailbox,
        sink: @escaping @MainActor @Sendable ([PaneId: SessionStatusPublication]) async -> Void
    ) {
        self.mailbox = mailbox
        self.sink = sink
    }

    package func publishPending() async {
        let batch = mailbox.takeBatch()
        if !batch.isEmpty { await sink(batch) }
    }
}
