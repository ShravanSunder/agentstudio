extension BridgeProductSession {
    func subscriptionSnapshot(
        subscriptionId: String
    ) -> BridgeProductSubscriptionSnapshot? {
        subscriptionState.snapshot(subscriptionId: subscriptionId)
    }

    var diagnosticSnapshot: BridgeProductSessionDiagnosticSnapshot {
        .init(
            activeEscapeEffectCount: activeEscapeEffectIds.count,
            activeOperationExecutionCount: operationTable.executionTasksById.count,
            mutationWatchCount: operationTable.mutationWatchesById.count,
            observationWaiterCount: operationTable.mutationWatchesById.values.reduce(0) {
                $0 + $1.observers.count
            },
            retainedOperationResultCount: operationTable.entriesById.count,
            pendingControlCount: pendingControl == nil ? 0 : 1,
            activeSubscriptionCount: subscriptionState.snapshots().count,
            producerFrameWaiterCount: producerFrameWaitersByLease.count,
            producerPacingWaiterCount: producerObservationPacingWaitersByLease.values.reduce(0) {
                $0 + $1.count
            },
            producerRetirementCount: producerRetirementStateByLease.count,
            producer: producerSnapshot()
        )
    }
}
