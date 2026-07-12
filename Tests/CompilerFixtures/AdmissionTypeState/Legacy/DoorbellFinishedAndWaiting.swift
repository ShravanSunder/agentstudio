func constructDoorbellFinishedAndWaiting() -> AdmissionDoorbellStateSnapshot {
    AdmissionDoorbellStateSnapshot(
        hasPendingSignal: false,
        hasWaitingConsumer: true,
        isFinished: true
    )
}
