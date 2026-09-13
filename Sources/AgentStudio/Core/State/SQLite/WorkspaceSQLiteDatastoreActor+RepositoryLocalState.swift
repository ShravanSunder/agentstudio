import Foundation

extension WorkspaceSQLiteDatastoreActor {
    func loadApplicationEntityRecency() async -> ApplicationEntityRecencyLoadResult {
        do {
            let repository = try preparedApplicationLocalRepository()
            return .loaded(try repository.fetchApplicationEntityRecency().filter(admitsRepositoryRecency))
        } catch {
            return .unavailable(.init(error))
        }
    }

    func saveApplicationEntityRecency(_ recentEntities: [ApplicationEntityRecency]) async throws {
        let repository = try preparedApplicationLocalRepository()
        let admitted = recentEntities.filter(admitsRepositoryRecency)
        try repository.replaceApplicationEntityRecency(admitted)
    }

    func loadRepositoryLocalActivity() async -> RepositoryLocalActivityLoadResult {
        do {
            let repository = try preparedApplicationLocalRepository()
            return .loaded(filterRetiredRepositoryActivity(try repository.fetchRepositoryLocalActivitySnapshot()))
        } catch {
            return .unavailable(.init(error))
        }
    }

    func commitRepositoryLocalActivity(
        _ commit: RepositoryLocalActivityCommit
    ) async throws -> RepositoryLocalActivitySnapshot {
        let repository = try preparedApplicationLocalRepository()
        let admitted: RepositoryLocalActivityCommit
        if let surviving = retentionSurvivingIdentity {
            let unsettled = try repository.unsettledRepositoryRetentionKeys()
            admitted = try RepositoryLocalActivityCommit(
                repositoryUpdates: commit.repositoryUpdates.filter {
                    surviving.repositoryKeys.contains($0.repositoryStableKey)
                        || unsettled.contains($0.repositoryStableKey)
                }, cursorWatermarks: commit.cursorWatermarks, updatedAt: commit.updatedAt
            )
        } else {
            admitted = commit
        }
        return filterRetiredRepositoryActivity(try repository.commitRepositoryLocalActivity(admitted))
    }

    private func admitsRepositoryRecency(_ recency: ApplicationEntityRecency) -> Bool {
        guard let surviving = retentionSurvivingIdentity else { return true }
        switch recency.entity {
        case .repository(let key): return surviving.repositoryKeys.contains(key)
        case .worktree(let key): return surviving.worktreeKeys.contains(key)
        }
    }

    private func filterRetiredRepositoryActivity(_ snapshot: RepositoryLocalActivitySnapshot)
        -> RepositoryLocalActivitySnapshot
    {
        guard let surviving = retentionSurvivingIdentity else { return snapshot }
        return .init(
            activityByRepositoryStableKey: snapshot.activityByRepositoryStableKey.filter {
                surviving.repositoryKeys.contains($0.key) || $0.value.ownedPromotionUnsettled
            }, cursorByVolumeIdentifier: snapshot.cursorByVolumeIdentifier
        )
    }

}
