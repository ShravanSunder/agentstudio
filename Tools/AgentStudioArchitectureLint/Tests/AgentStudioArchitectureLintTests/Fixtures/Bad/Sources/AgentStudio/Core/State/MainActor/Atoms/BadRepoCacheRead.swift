func badRepoCacheRead(repoCache: RepoCacheAtom) -> Int {
    repoCache.worktreeEnrichmentByWorktreeId.count
}
