extension BridgePaneProductSchemeProvider {
    func claimComparisonTargetReservation(
        for request: BridgeProductContentRequest
    ) -> BridgeProductReviewComparisonTargetsReservation? {
        guard case .reviewComparisonTargets(let comparisonRequest) = request else {
            return nil
        }
        let reservation = consumeComparisonTargetReservation(comparisonRequest)
        comparisonTargetCatalogTraceRecorder?.submit(
            BridgeReviewComparisonTargetCatalogTraceEvent(
                stage: .reservationClaim,
                outcome: reservation == nil ? .inactive : .claimed,
                queryRequestSequence: reservation?.queryRequestSequence,
                durationMilliseconds: nil,
                reservationAgeMilliseconds: reservation.map {
                    BridgeReviewComparisonTargetCatalogTraceEvent.milliseconds(
                        from: $0.issuedAt.duration(to: ContinuousClock.now)
                    )
                },
                inputRowCount: nil,
                outputRowCount: nil,
                observedByteCount: nil,
                isTruncated: nil
            )
        )
        return reservation
    }

    func consumeComparisonTargetReservation(
        _ request: BridgeProductReviewComparisonTargetsContentRequest
    ) -> BridgeProductReviewComparisonTargetsReservation? {
        guard let reservation = pendingComparisonTargetReservation,
            reservation.matches(request)
        else { return nil }
        pendingComparisonTargetReservation = nil
        return reservation
    }

    func invalidatePendingComparisonTargetReservation() {
        pendingComparisonTargetReservation = nil
    }

    func recordComparisonTargetCatalogTrace(
        stage: BridgeReviewComparisonTargetCatalogTraceEvent.Stage,
        outcome: BridgeReviewComparisonTargetCatalogTraceEvent.Outcome,
        queryRequestSequence: Int,
        duration: Duration
    ) {
        comparisonTargetCatalogTraceRecorder?.submit(
            BridgeReviewComparisonTargetCatalogTraceEvent(
                stage: stage,
                outcome: outcome,
                queryRequestSequence: queryRequestSequence,
                durationMilliseconds:
                    BridgeReviewComparisonTargetCatalogTraceEvent.milliseconds(from: duration),
                reservationAgeMilliseconds: nil,
                inputRowCount: nil,
                outputRowCount: nil,
                observedByteCount: nil,
                isTruncated: nil
            )
        )
    }
}
