func attachWaitingStateToCurrentFinishedDoorbell() -> AdmissionDoorbellStateSnapshot {
    .finished(hasWaitingConsumer: true)
}
