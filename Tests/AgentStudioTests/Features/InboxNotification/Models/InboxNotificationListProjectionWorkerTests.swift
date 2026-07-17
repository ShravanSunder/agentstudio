import Foundation
import Testing

@testable import AgentStudio

@Suite("InboxNotificationListProjectionWorker")
struct InboxNotificationListProjectionWorkerTests {
    private enum CancellationProbe: Error {
        case cancelled
    }

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
            trigger: .search,
            repoPresentationByRepoId: [:]
        )

        let result = try await InboxNotificationListProjectionWorker().project(request)

        #expect(result.generation == 7)
        #expect(result.key == key)
        #expect(result.trigger == .search)
        #expect(result.model.sections.visibleNotificationIds == [matchingNotification.id])
    }

    @Test("list model checks cancellation between expensive projection stages")
    func listModelChecksCancellationBetweenProjectionStages() {
        var checkpointCount = 0

        #expect(throws: CancellationProbe.cancelled) {
            _ = try InboxNotificationListModel(
                notifications: [
                    notification(id: UUID(), timestamp: Date(), title: "Build finished")
                ],
                grouping: .none,
                sort: .newestFirst,
                searchText: "build",
                contentMode: .all,
                rowStateFilter: .all,
                filter: nil,
                collapsedGroups: [],
                repoPresentation: { _ in nil },
                cancellationCheck: {
                    checkpointCount += 1
                    if checkpointCount == 3 {
                        throw CancellationProbe.cancelled
                    }
                }
            )
        }
        #expect(checkpointCount == 3)
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
