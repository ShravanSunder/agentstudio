import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

package struct InboxNotificationListProjectionKey: Equatable, Sendable {
    package let notifications: [InboxNotification]
    package let grouping: InboxNotificationGrouping
    package let sort: InboxNotificationSort
    package let searchText: String
    package let filter: InboxFilter?
    package let contentMode: InboxNotificationContentMode
    package let rowStateFilter: InboxNotificationRowStateFilter
    package let collapsedGroups: Set<InboxNotificationGroupKey>
    package let repoPresentationFingerprint: String

    package init(
        notifications: [InboxNotification],
        grouping: InboxNotificationGrouping,
        sort: InboxNotificationSort,
        searchText: String,
        filter: InboxFilter?,
        contentMode: InboxNotificationContentMode,
        rowStateFilter: InboxNotificationRowStateFilter,
        collapsedGroups: Set<InboxNotificationGroupKey>,
        repoPresentationFingerprint: String
    ) {
        self.notifications = notifications
        self.grouping = grouping
        self.sort = sort
        self.searchText = searchText
        self.filter = filter
        self.contentMode = contentMode
        self.rowStateFilter = rowStateFilter
        self.collapsedGroups = collapsedGroups
        self.repoPresentationFingerprint = repoPresentationFingerprint
    }
}

package struct InboxNotificationListProjectionRequest: Equatable, Sendable {
    package let generation: Int
    package let key: InboxNotificationListProjectionKey
    package let trigger: AppPolicies.SidebarProjection.Trigger
    package let repoPresentationByRepoId: [UUID: InboxNotificationRepoGroupPresentation]

    package init(
        generation: Int,
        key: InboxNotificationListProjectionKey,
        trigger: AppPolicies.SidebarProjection.Trigger,
        repoPresentationByRepoId: [UUID: InboxNotificationRepoGroupPresentation]
    ) {
        self.generation = generation
        self.key = key
        self.trigger = trigger
        self.repoPresentationByRepoId = repoPresentationByRepoId
    }
}

package struct InboxNotificationListProjectionResult: Equatable, Sendable {
    package let generation: Int
    package let key: InboxNotificationListProjectionKey
    package let trigger: AppPolicies.SidebarProjection.Trigger
    package let model: InboxNotificationListModel
    package let workerDuration: Duration

    package init(
        generation: Int,
        key: InboxNotificationListProjectionKey,
        trigger: AppPolicies.SidebarProjection.Trigger,
        model: InboxNotificationListModel,
        workerDuration: Duration
    ) {
        self.generation = generation
        self.key = key
        self.trigger = trigger
        self.model = model
        self.workerDuration = workerDuration
    }
}

package actor InboxNotificationListProjectionWorker {
    package init() {}

    package func project(_ request: InboxNotificationListProjectionRequest) async throws
        -> InboxNotificationListProjectionResult
    {
        // Runs CPU-bound list projection outside actor/main-actor isolation; cancellation is forwarded below.
        // swiftlint:disable:next no_task_detached
        let projectionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let clock = ContinuousClock()
            let start = clock.now
            let model = try InboxNotificationListModel(
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
                },
                cancellationCheck: { try Task.checkCancellation() }
            )
            try Task.checkCancellation()
            return InboxNotificationListProjectionResult(
                generation: request.generation,
                key: request.key,
                trigger: request.trigger,
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
