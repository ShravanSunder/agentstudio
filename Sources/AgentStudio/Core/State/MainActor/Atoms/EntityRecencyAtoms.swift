import AgentStudioInfrastructure
import Foundation
import Observation

@MainActor
@Observable
package final class ApplicationEntityRecencyAtom {
    package private(set) var recentEntities: [ApplicationEntityRecency] = []
    package private(set) var hydrationDisposition: ApplicationEntityRecencyHydrationDisposition = .pending
    @ObservationIgnored private let now: @MainActor @Sendable () -> Date

    package init(now: @escaping @MainActor @Sendable () -> Date = Date.init) {
        self.now = now
    }

    package func record(_ recency: ApplicationEntityRecency) {
        recentEntities = Self.normalized(
            recentEntities + [recency],
            referenceDate: now()
        )
    }

    package func recordOpened(
        repositoryStableKey: String,
        worktreeStableKey: String,
        at timestamp: Date
    ) throws {
        let repositoryRecency = try ApplicationEntityRecency(
            entity: .repository(repositoryStableKey: repositoryStableKey),
            interaction: .opened,
            lastInteractedAt: timestamp
        )
        let worktreeRecency = try ApplicationEntityRecency(
            entity: .worktree(worktreeStableKey: worktreeStableKey),
            interaction: .opened,
            lastInteractedAt: timestamp
        )
        recentEntities = Self.normalized(
            recentEntities + [repositoryRecency, worktreeRecency],
            referenceDate: now()
        )
    }

    package func hydrate(_ recentEntities: [ApplicationEntityRecency]) {
        self.recentEntities = Self.normalized(recentEntities, referenceDate: now())
        hydrationDisposition = .authoritative
    }

    package func remove(_ entity: ApplicationRecentEntity) {
        recentEntities.removeAll { $0.entity == entity }
    }

    package func clear() {
        recentEntities = []
        hydrationDisposition = .authoritative
    }

    private static func normalized(
        _ recentEntities: [ApplicationEntityRecency],
        referenceDate: Date
    ) -> [ApplicationEntityRecency] {
        var newestByIdentity: [ApplicationRecentEntity: ApplicationEntityRecency] = [:]
        for recency in recentEntities {
            guard
                let current = newestByIdentity[recency.entity],
                current.lastInteractedAt >= recency.lastInteractedAt
            else {
                newestByIdentity[recency.entity] = recency
                continue
            }
        }

        let cutoff = referenceDate.addingTimeInterval(
            -AppPolicies.EntityRecency.applicationActivityHorizon
        )
        return newestByIdentity.values
            .filter { $0.lastInteractedAt >= cutoff }
            .sorted(by: recencyPrecedes)
    }

    private static func recencyPrecedes(
        _ lhs: ApplicationEntityRecency,
        _ rhs: ApplicationEntityRecency
    ) -> Bool {
        if lhs.lastInteractedAt != rhs.lastInteractedAt {
            return lhs.lastInteractedAt > rhs.lastInteractedAt
        }
        if lhs.entity.storageKind != rhs.entity.storageKind {
            return lhs.entity.storageKind < rhs.entity.storageKind
        }
        return lhs.entity.storageKey < rhs.entity.storageKey
    }
}

@MainActor
@Observable
package final class WorkspaceEntityRecencyAtom {
    package private(set) var workspaceID: UUID?
    package private(set) var recentEntities: [WorkspaceEntityRecency] = []
    @ObservationIgnored private let recencyFamily = AtomFamily<WorkspaceRecentEntity, WorkspaceEntityRecency>(
        telemetryLabel: "workspace_entity_recency",
        isContentEqual: ==
    )
    @ObservationIgnored private let acceptedCommitRevision = AtomRevision()

    package init() {}

    package func record(_ recency: WorkspaceEntityRecency) {
        guard workspaceID == recency.workspaceID else { return }
        replaceRecentEntities(Self.normalized(recentEntities + [recency]))
    }

    package func hydrate(workspaceID: UUID, recentEntities: [WorkspaceEntityRecency]) {
        self.workspaceID = workspaceID
        replaceRecentEntities(
            Self.normalized(recentEntities.filter { $0.workspaceID == workspaceID })
        )
    }

    package func remove(_ entity: WorkspaceRecentEntity) {
        replaceRecentEntities(recentEntities.filter { $0.entity != entity })
    }

    package func clear() {
        workspaceID = nil
        replaceRecentEntities([])
    }

    package func recency(for entity: WorkspaceRecentEntity) -> WorkspaceEntityRecency? {
        recencyFamily.value(for: entity)
    }

    private func replaceRecentEntities(_ replacement: [WorkspaceEntityRecency]) {
        recentEntities = replacement
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        recencyFamily.replaceAll(
            Dictionary(uniqueKeysWithValues: replacement.map { ($0.entity, $0) }),
            mutation: mutation
        )
        mutation.commit()
    }

    private static func normalized(
        _ recentEntities: [WorkspaceEntityRecency]
    ) -> [WorkspaceEntityRecency] {
        var newestByEntity: [WorkspaceRecentEntity: WorkspaceEntityRecency] = [:]
        for recency in recentEntities {
            guard
                let current = newestByEntity[recency.entity],
                current.lastInteractedAt >= recency.lastInteractedAt
            else {
                newestByEntity[recency.entity] = recency
                continue
            }
        }

        return newestByEntity.values
            .sorted {
                if $0.lastInteractedAt != $1.lastInteractedAt {
                    return $0.lastInteractedAt > $1.lastInteractedAt
                }
                return $0.entity.storageKey < $1.entity.storageKey
            }
            .prefix(AppPolicies.EntityRecency.maximumWorkspaceRetainedEntityCount)
            .map(\.self)
    }
}
