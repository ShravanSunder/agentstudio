extension BoundedGatherMailbox {
    func diagnostics(state: State) -> Duration? {
        state.oldestPendingNode?.retainedAt
    }

    func takeBoundedLease(
        keyState: inout KeyState,
        limits: GatherMailboxLimits
    ) -> [RetainedContribution] {
        var contributions: [RetainedContribution] = []
        var currentNode = keyState.pendingHead
        var itemCount = 0
        var byteCount = 0

        while let node = currentNode,
            contributions.count < limits.maximumContributionsPerLease,
            itemCount + node.retained.footprint.itemCount <= limits.maximumItemsPerLease,
            byteCount + node.retained.footprint.byteCount <= limits.maximumBytesPerLease
        {
            contributions.append(node.retained)
            itemCount += node.retained.footprint.itemCount
            byteCount += node.retained.footprint.byteCount
            currentNode = node.next
        }
        return contributions
    }

    func performCleanup(
        state: inout State,
        quantum: AdmissionCleanupQuantum
    ) -> Int {
        var releasedEntryCount = 0
        var currentNode = state.cleanupHead

        while let node = currentNode,
            releasedEntryCount < quantum.maximumEntries
        {
            releasedEntryCount += 1
            currentNode = node.next
        }
        return releasedEntryCount
    }
}
