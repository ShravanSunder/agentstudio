import Foundation

extension GitWorkingDirectoryProjector {
    func prepareRemoteReferenceCurrentStatus(
        _ status: GitWorkingTreeStatus,
        changeset: FileChangeset
    ) async -> GitWorkingTreeStatus {
        if shouldCheckOrigin(for: changeset) {
            await emitOriginResolutionIfChanged(changeset: changeset, statusSnapshot: status)
        }
        return statusWithCurrentRemoteReferenceAuthority(status, repoId: changeset.repoId)
    }

    package func applyRemoteReferenceAuthorityUpdate(_ update: RemoteReferenceAuthorityUpdate) {
        guard !isShuttingDown else { return }
        let repoId = update.repoId
        guard update.authorityRevision > (remoteReferenceAuthorityRevisionByRepoId[repoId] ?? 0) else {
            return
        }
        remoteReferenceAuthorityRevisionByRepoId[repoId] = update.authorityRevision

        switch update {
        case .invalidated:
            remoteReferenceAcceptanceByRepoId.removeValue(forKey: repoId)
        case .localAccepted(let acceptance):
            installRemoteReferenceAuthority(acceptance)
        case .promoted(let acceptance, let representedWorktreeIds):
            guard installRemoteReferenceAuthority(acceptance) else { return }
            beginRemoteReferenceRecomputation(
                acceptance: acceptance,
                representedWorktreeIds: representedWorktreeIds
            )
        }
    }

    @discardableResult
    private func installRemoteReferenceAuthority(_ acceptance: RemoteReferenceAcceptance) -> Bool {
        guard lastKnownOriginByRepoId[acceptance.repoId] == acceptance.expectedOrigin else {
            remoteReferenceAcceptanceByRepoId.removeValue(forKey: acceptance.repoId)
            return false
        }
        remoteReferenceAcceptanceByRepoId[acceptance.repoId] = acceptance
        return true
    }

    func statusWithCurrentRemoteReferenceAuthority(
        _ status: GitWorkingTreeStatus,
        repoId: UUID
    ) -> GitWorkingTreeStatus {
        let currentOrigin: String?
        if case .resolved(let origin) = status.originResolution {
            currentOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            currentOrigin = nil
        }
        return Self.statusWithCurrentRemoteReferenceAuthority(
            status,
            acceptedOrigin: remoteReferenceAcceptanceByRepoId[repoId]?.expectedOrigin,
            currentOrigin: currentOrigin
        )
    }

    nonisolated static func statusWithCurrentRemoteReferenceAuthority(
        _ status: GitWorkingTreeStatus,
        acceptedOrigin: String?,
        currentOrigin: String?
    ) -> GitWorkingTreeStatus {
        guard let currentOrigin, acceptedOrigin == currentOrigin else {
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(
                    changed: status.summary.changed,
                    staged: status.summary.staged,
                    untracked: status.summary.untracked,
                    linesAdded: status.summary.linesAdded,
                    linesDeleted: status.summary.linesDeleted,
                    aheadCount: nil,
                    behindCount: nil,
                    hasUpstream: status.summary.hasUpstream
                ),
                branch: status.branch,
                originResolution: status.originResolution,
                entries: status.entries,
                containsPathIdentityAmbiguity: status.containsPathIdentityAmbiguity
            )
        }
        return status
    }
}
