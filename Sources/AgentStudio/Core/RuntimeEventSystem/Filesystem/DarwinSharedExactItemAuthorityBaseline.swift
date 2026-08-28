import Foundation

struct DarwinSharedExactItemAuthorityBaseline: Equatable, Sendable {
    let authority: GitCleanContinuityAuthority
    let bindingGeneration: UInt64
    let exactItemsByParent: [DarwinSharedExactItemParentKey: Set<String>]
    let streamGenerationByParent: [DarwinSharedExactItemParentKey: UInt64]
    let fingerprintsByCanonicalPath: [String: DarwinSharedExactItemFingerprint]

    var canonicalItemPaths: Set<String> {
        Set(exactItemsByParent.values.flatMap { $0 })
    }

    func matches(
        authority: GitCleanContinuityAuthority,
        lease: DarwinSharedExactItemBindingLease
    ) -> Bool {
        self.authority == authority
            && bindingGeneration == lease.bindingGeneration
            && exactItemsByParent == lease.exactItemsByParent
            && streamGenerationByParent == lease.streamGenerationByParent
            && Set(fingerprintsByCanonicalPath.keys) == canonicalItemPaths
    }
}

struct DarwinSharedExactItemAuthorityBaselines {
    private var baselineByWorktreeId: [UUID: DarwinSharedExactItemAuthorityBaseline] = [:]

    mutating func install(
        worktreeId: UUID,
        authority: GitCleanContinuityAuthority,
        lease: DarwinSharedExactItemBindingLease,
        snapshot: DarwinSharedExactItemFingerprintSnapshot
    ) -> DarwinSharedExactItemAuthorityBaseline? {
        let baseline = DarwinSharedExactItemAuthorityBaseline(
            authority: authority,
            bindingGeneration: lease.bindingGeneration,
            exactItemsByParent: lease.exactItemsByParent,
            streamGenerationByParent: lease.streamGenerationByParent,
            fingerprintsByCanonicalPath: snapshot.fingerprintsByCanonicalPath
        )
        guard Set(snapshot.fingerprintsByCanonicalPath.keys) == baseline.canonicalItemPaths else {
            return nil
        }
        baselineByWorktreeId[worktreeId] = baseline
        return baseline
    }

    func baseline(
        worktreeId: UUID,
        authority: GitCleanContinuityAuthority,
        lease: DarwinSharedExactItemBindingLease
    ) -> DarwinSharedExactItemAuthorityBaseline? {
        guard let baseline = baselineByWorktreeId[worktreeId],
            baseline.matches(authority: authority, lease: lease)
        else {
            return nil
        }
        return baseline
    }

    mutating func remove(worktreeId: UUID) {
        baselineByWorktreeId.removeValue(forKey: worktreeId)
    }

    mutating func removeAll() {
        baselineByWorktreeId.removeAll(keepingCapacity: false)
    }
}
