func attachWaitingStateToCurrentPendingDoorbell() -> AdmissionDoorbellStateSnapshot {
    .signalPending(hasWaitingConsumer: true)
}
