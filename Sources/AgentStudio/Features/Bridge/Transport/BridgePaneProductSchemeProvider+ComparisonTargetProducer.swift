import Foundation

extension BridgePaneProductSchemeProvider {
    enum BufferedContentDeliveryDisposition: Equatable, Sendable {
        case cancelled
        case complete
        case deliveryFailed
    }

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
        guard
            let producedCatalog = try await produceComparisonTargetCatalog(
                for: reservation,
                lease: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                session: session
            )
        else { return }
        let deliveryDisposition: BufferedContentDeliveryDisposition
        do {
            deliveryDisposition = try await runBufferedContentProducer(
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
        } catch is CancellationError {
            recordComparisonTargetTerminal(
                outcome: .cancelled,
                reservation: reservation,
                observedByteCount: nil
            )
            return
        } catch {
            recordComparisonTargetTerminal(
                outcome: Task.isCancelled ? .cancelled : .productionFailed,
                reservation: reservation,
                observedByteCount: nil
            )
            return
        }
        switch deliveryDisposition {
        case .cancelled:
            recordComparisonTargetTerminal(
                outcome: .cancelled,
                reservation: reservation,
                observedByteCount: nil
            )
        case .complete:
            recordComparisonTargetTerminal(
                outcome: .complete,
                reservation: reservation,
                observedByteCount: producedCatalog.body.count
            )
        case .deliveryFailed:
            recordComparisonTargetTerminal(
                outcome: .productionFailed,
                reservation: reservation,
                observedByteCount: nil
            )
        }
    }

    private func produceComparisonTargetCatalog(
        for reservation: BridgeProductReviewComparisonTargetsReservation,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws -> BridgeReviewComparisonTargetProducedCatalog? {
        do {
            try Task.checkCancellation()
            let producedCatalog =
                try await reviewComparisonTargetCatalogProducer
                .produceComparisonTargetCatalog(for: reservation)
            try Task.checkCancellation()
            return producedCatalog
        } catch is CancellationError {
            recordComparisonTargetTerminal(
                outcome: .cancelled,
                reservation: reservation,
                observedByteCount: nil
            )
            return nil
        } catch {
            guard !Task.isCancelled else {
                recordComparisonTargetTerminal(
                    outcome: .cancelled,
                    reservation: reservation,
                    observedByteCount: nil
                )
                return nil
            }
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
            return nil
        }
    }

    func isContentAdmissionValid(
        _ foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        reservation: BridgeProductReviewComparisonTargetsReservation?
    ) -> Bool {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            recordClaimedComparisonTargetCancellation(reservation)
            return false
        }
        return true
    }

    func recordClaimedComparisonTargetFailure(
        _ error: any Error,
        reservation: BridgeProductReviewComparisonTargetsReservation?
    ) {
        recordClaimedComparisonTargetTerminal(
            outcome: error is CancellationError || Task.isCancelled ? .cancelled : .productionFailed,
            reservation: reservation
        )
    }

    func recordClaimedComparisonTargetCancellation(
        _ reservation: BridgeProductReviewComparisonTargetsReservation?
    ) {
        recordClaimedComparisonTargetTerminal(
            outcome: .cancelled,
            reservation: reservation
        )
    }

    func recordClaimedComparisonTargetTerminal(
        outcome: BridgeReviewComparisonTargetCatalogTraceEvent.Outcome,
        reservation: BridgeProductReviewComparisonTargetsReservation?
    ) {
        guard let reservation else { return }
        recordComparisonTargetTerminal(
            outcome: outcome,
            reservation: reservation,
            observedByteCount: nil
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
