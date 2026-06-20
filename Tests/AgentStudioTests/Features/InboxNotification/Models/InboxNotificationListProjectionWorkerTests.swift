import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListProjectionWorker")
struct InboxNotificationListProjectionWorkerTests {
    @Test("worker projects list model off caller isolation and preserves generation")
    func workerProjectsListModelAndPreservesGeneration() async throws {
        let matchingNotification = notification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            title: "Build finished"
        )
        let filteredNotification = notification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 200),
            title: "Approval requested"
        )
        let key = InboxNotificationListProjectionKey(
            notifications: [filteredNotification, matchingNotification],
            grouping: .none,
            sort: .oldestFirst,
            searchText: "build",
            filter: nil,
            contentMode: .all,
            rowStateFilter: .all,
            collapsedGroups: [],
            repoPresentationFingerprint: ""
        )
        let request = InboxNotificationListProjectionRequest(
            generation: 7,
            key: key,
            repoPresentationByRepoId: [:]
        )

        let result = try await InboxNotificationListProjectionWorker().project(request)

        #expect(result.generation == 7)
        #expect(result.key == key)
        #expect(result.model.sections.visibleNotificationIds == [matchingNotification.id])
    }

    private func notification(
        id: UUID,
        timestamp: Date,
        title: String
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: timestamp,
            kind: .agentRpc,
            title: title,
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
