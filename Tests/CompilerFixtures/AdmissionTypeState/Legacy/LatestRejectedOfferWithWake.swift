func constructLatestRejectedOfferWithWake() -> LatestValueOfferResult {
    LatestValueOfferResult(
        receipt: .physicalCapacityExceeded,
        wake: .scheduleDrain
    )
}
