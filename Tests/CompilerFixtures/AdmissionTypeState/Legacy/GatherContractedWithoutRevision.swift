func constructGatherContractedAdmissionWithoutRevision() -> GatherAdmissionReceipt<Int> {
    GatherAdmissionReceipt(
        payload: .contractedToRecovery,
        recoveryRevision: nil
    )
}
