package enum PaneContextPublication: Sendable, Equatable {
    case set(PaneContextDisplay)
    case remove
}

package struct PaneContextPublicationCounts: Sendable, Equatable {
    package let computed: Int
    package let suppressed: Int
    package let coalesced: Int
}

/// RED shell; distinctness and the latest-value mailbox are asserted first.
package final class PaneContextPublicationMailbox: Sendable {
    package init() {}

    @discardableResult
    package func offer(_ display: PaneContextDisplay, for paneId: PaneId) -> Bool { false }
    package func retire(_ paneId: PaneId) {}
    package func reconcile(_ displays: [PaneId: PaneContextDisplay]) {}
    package func takeBatch() -> [PaneId: PaneContextPublication] { [:] }
    package func counts() -> PaneContextPublicationCounts { .init(computed: 0, suppressed: 0, coalesced: 0) }
    package func close() {}
}

package actor PaneContextPublicationLane {
    package nonisolated let mailbox: PaneContextPublicationMailbox

    package init(
        mailbox: PaneContextPublicationMailbox,
        sink: @escaping @MainActor @Sendable ([PaneId: PaneContextPublication]) async -> Void
    ) {
        self.mailbox = mailbox
    }

    package func start() {}
    package func publishPending() async {}
    package func shutdown() async {}
}
