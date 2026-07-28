import Foundation
import Observation

@MainActor
@Observable
final class ApplicationEntityRecencyAtom {
    private(set) var recentEntities: [ApplicationEntityRecency] = []

    func record(_ recency: ApplicationEntityRecency) {
        recentEntities = Self.normalized(recentEntities + [recency])
    }

    func recordOpened(
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
        recentEntities = Self.normalized(recentEntities + [repositoryRecency, worktreeRecency])
    }

    func hydrate(_ recentEntities: [ApplicationEntityRecency]) {
        self.recentEntities = Self.normalized(recentEntities)
    }

    func remove(_ entity: ApplicationRecentEntity) {
        recentEntities.removeAll { $0.entity == entity }
    }

    func clear() {
        recentEntities = []
    }

    private static func normalized(
        _ recentEntities: [ApplicationEntityRecency]
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

        let sorted = newestByIdentity.values.sorted(by: recencyPrecedes)
        var retainedCountByKind: [String: Int] = [:]
        return sorted.filter { recency in
            let kind = recency.entity.storageKind
            let retainedCount = retainedCountByKind[kind, default: 0]
            guard retainedCount < AppPolicies.EntityRecency.maximumRetainedEntityCountPerKind else {
                return false
            }
            retainedCountByKind[kind] = retainedCount + 1
            return true
        }
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
final class WorkspaceEntityRecencyAtom {
    private(set) var workspaceID: UUID?
    private(set) var recentEntities: [WorkspaceEntityRecency] = []

    func record(_ recency: WorkspaceEntityRecency) {
        guard workspaceID == recency.workspaceID else { return }
        recentEntities = Self.normalized(recentEntities + [recency])
    }

    func hydrate(workspaceID: UUID, recentEntities: [WorkspaceEntityRecency]) {
        self.workspaceID = workspaceID
        self.recentEntities = Self.normalized(
            recentEntities.filter { $0.workspaceID == workspaceID }
        )
    }

    func remove(_ entity: WorkspaceRecentEntity) {
        recentEntities.removeAll { $0.entity == entity }
    }

    func clear() {
        workspaceID = nil
        recentEntities = []
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
            .prefix(AppPolicies.EntityRecency.maximumRetainedEntityCountPerKind)
            .map(\.self)
    }
}
