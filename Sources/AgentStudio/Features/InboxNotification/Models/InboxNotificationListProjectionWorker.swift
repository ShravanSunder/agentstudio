import Foundation

struct InboxNotificationListProjectionKey: Equatable, Sendable {
    let notifications: [InboxNotification]
    let grouping: InboxNotificationGrouping
    let sort: InboxNotificationSort
    let searchText: String
    let filter: InboxFilter?
    let contentMode: InboxNotificationContentMode
    let rowStateFilter: InboxNotificationRowStateFilter
    let collapsedGroups: Set<InboxNotificationGroupKey>
    let repoPresentationFingerprint: String
}

struct InboxNotificationListProjectionRequest: Equatable, Sendable {
    let generation: Int
    let key: InboxNotificationListProjectionKey
    let repoPresentationByRepoId: [UUID: InboxNotificationRepoGroupPresentation]
}

struct InboxNotificationListProjectionResult: Equatable, Sendable {
    let generation: Int
    let key: InboxNotificationListProjectionKey
    let model: InboxNotificationListModel
    let workerDuration: Duration
}

actor InboxNotificationListProjectionWorker {
    func project(_ request: InboxNotificationListProjectionRequest) async throws
        -> InboxNotificationListProjectionResult
    {
        // Runs CPU-bound list projection outside actor/main-actor isolation; cancellation is forwarded below.
        // swiftlint:disable:next no_task_detached
        let projectionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let clock = ContinuousClock()
            let start = clock.now
            let model = InboxNotificationListModel(
                notifications: request.key.notifications,
                grouping: request.key.grouping,
                sort: request.key.sort,
                searchText: request.key.searchText,
                contentMode: request.key.contentMode,
                rowStateFilter: request.key.rowStateFilter,
                filter: request.key.filter,
                collapsedGroups: request.key.collapsedGroups,
                repoPresentation: { repoId in
                    guard let repoId else { return nil }
                    return request.repoPresentationByRepoId[repoId]
                }
            )
            try Task.checkCancellation()
            return InboxNotificationListProjectionResult(
                generation: request.generation,
                key: request.key,
                model: model,
                workerDuration: start.duration(to: clock.now)
            )
        }

        return try await withTaskCancellationHandler {
            try await projectionTask.value
        } onCancel: {
            projectionTask.cancel()
        }
    }
}
