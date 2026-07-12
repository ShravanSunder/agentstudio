func constructGatherRejectedOfferWithWake() -> GatherOfferResult<Int> {
    GatherOfferResult(
        receipt: .staleGeneration,
        wake: .scheduleDrain
    )
}
