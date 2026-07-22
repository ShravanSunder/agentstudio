extension BridgeWorktreeProductConstructionCoordinator {
    func snapshot() -> BridgeWorktreeProductConstructionSnapshot {
        makeSnapshot(entries: entriesByNonce.values)
    }

    func snapshot(replacing entry: BridgeConstructionEntry) -> BridgeWorktreeProductConstructionSnapshot {
        var currentEntries = entriesByNonce
        currentEntries[entry.nonce] = entry
        return makeSnapshot(entries: currentEntries.values)
    }

    private func makeSnapshot<Entries: Sequence>(
        entries: Entries
    ) -> BridgeWorktreeProductConstructionSnapshot where Entries.Element == BridgeConstructionEntry {
        var waiterCount = 0
        var leaseCount = 0
        var payloadCount = 0
        var inFlightCount = 0
        var locatorCount = 0
        var tombstoneCount = 0
        var retainedByteCount = 0

        var entryCount = 0
        for entry in entries {
            entryCount += 1
            waiterCount +=
                entry.waiters.count
                + (entry.progressiveFileState?.pendingReadCount ?? 0)
            leaseCount += entry.activeLeaseNonces.count
            inFlightCount += entry.isInFlight ? 1 : 0
            switch entry.phase {
            case .building:
                retainedByteCount += entry.progressiveFileState?.retainedByteCount ?? 0
            case .ready(let artifact):
                payloadCount += 1
                locatorCount += artifact.contentLocatorCount
                retainedByteCount += artifact.retainedByteCount
            case .tombstone:
                tombstoneCount += 1
            }
        }

        return BridgeWorktreeProductConstructionSnapshot(
            entryCount: entryCount,
            waiterCount: waiterCount,
            leaseCount: leaseCount,
            payloadCount: payloadCount,
            inFlightCount: inFlightCount,
            locatorCount: locatorCount,
            drainingTombstoneCount: tombstoneCount,
            retainedArtifactByteCount: retainedByteCount
        )
    }
}
