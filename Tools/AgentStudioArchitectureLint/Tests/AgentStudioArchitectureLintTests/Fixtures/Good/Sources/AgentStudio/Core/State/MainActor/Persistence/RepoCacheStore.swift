struct RepoCacheStore {
    let repoCache: RepoCacheAtom

    func snapshotCount() -> Int {
        repoCache.repoEnrichmentByRepoId.count
    }
}
