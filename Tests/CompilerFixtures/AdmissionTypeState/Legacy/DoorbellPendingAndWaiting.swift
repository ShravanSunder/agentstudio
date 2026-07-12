func constructDoorbellPendingAndWaiting() -> AdmissionDoorbellStateSnapshot {
    AdmissionDoorbellStateSnapshot(
        hasPendingSignal: true,
        hasWaitingConsumer: true,
        isFinished: false
    )
}
