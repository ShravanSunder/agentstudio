func attachPendingStateToCurrentFinishedDoorbell() -> AdmissionDoorbellStateSnapshot {
    .finished(hasPendingSignal: true)
}
