import Foundation

extension BridgePaneProductSchemeProvider {
    func runComparisonTargetContentProducer(
        reservation: BridgeProductReviewComparisonTargetsReservation?,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        guard let reservation else {
            try await enqueueUnavailableContentTerminal(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
            comparisonTargetCatalogTraceRecorder?.submit(
                BridgeReviewComparisonTargetCatalogTraceEvent(
                    stage: .terminal,
                    outcome: .unsupportedContent,
                    queryRequestSequence: nil,
                    durationMilliseconds: nil,
                    reservationAgeMilliseconds: nil,
                    inputRowCount: nil,
                    outputRowCount: nil,
                    observedByteCount: nil,
                    isTruncated: nil
                )
            )
            return
        }
        let producedCatalog: BridgeReviewComparisonTargetProducedCatalog
        do {
            try Task.checkCancellation()
            producedCatalog =
                try await reviewComparisonTargetCatalogProducer
                .produceComparisonTargetCatalog(for: reservation)
            try Task.checkCancellation()
        } catch is CancellationError {
            recordComparisonTargetTerminal(
                outcome: .cancelled,
                reservation: reservation,
                observedByteCount: nil
            )
            return
        } catch {
            guard !Task.isCancelled else { return }
            try await enqueueComparisonTargetProductionFailureTerminal(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
            recordComparisonTargetTerminal(
                outcome: .productionFailed,
                reservation: reservation,
                observedByteCount: nil
            )
            return
        }
        try await runBufferedContentProducer(
            BufferedContentBody(
                data: producedCatalog.body,
                endOfSource: true,
                sha256: producedCatalog.sha256
            ),
            lease: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            session: session
        )
        recordComparisonTargetTerminal(
            outcome: .complete,
            reservation: reservation,
            observedByteCount: producedCatalog.body.count
        )
    }

    private func recordComparisonTargetTerminal(
        outcome: BridgeReviewComparisonTargetCatalogTraceEvent.Outcome,
        reservation: BridgeProductReviewComparisonTargetsReservation,
        observedByteCount: Int?
    ) {
        comparisonTargetCatalogTraceRecorder?.submit(
            BridgeReviewComparisonTargetCatalogTraceEvent(
                stage: .terminal,
                outcome: outcome,
                queryRequestSequence: reservation.queryRequestSequence,
                durationMilliseconds: nil,
                reservationAgeMilliseconds: nil,
                inputRowCount: nil,
                outputRowCount: nil,
                observedByteCount: observedByteCount,
                isTruncated: nil
            )
        )
    }

    private func enqueueComparisonTargetProductionFailureTerminal(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        _ = try await session.enqueueTerminalContentFrame(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { sequence in
                .content(
                    .init(
                        header: try .error(
                            contentSequence: sequence,
                            code: .internal,
                            retryable: true,
                            safeMessage: "Comparison targets are unavailable"
                        ),
                        payload: Data()
                    )
                )
            }
        )
    }

    func enqueueUnavailableContentTerminal(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        _ = try await session.enqueueTerminalContentFrame(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { sequence in
                .content(
                    .init(
                        header: try .error(
                            contentSequence: sequence,
                            code: .unsupportedContent,
                            retryable: false,
                            safeMessage: "Content descriptor is not active"
                        ),
                        payload: Data()
                    )
                )
            }
        )
    }
}
