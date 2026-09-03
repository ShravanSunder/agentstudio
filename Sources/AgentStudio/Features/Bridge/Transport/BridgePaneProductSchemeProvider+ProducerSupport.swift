import Foundation

extension BridgePaneProductSchemeProvider {
    struct BufferedContentBody: Sendable {
        let data: Data
        let endOfSource: Bool
        let sha256: String
    }

    struct FileContentStreamDigest: Sendable {
        let byteCount: Int
        let sha256: String
    }

    func beginActivityInvalidatedProducerRetirement(
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async -> BridgeProductProducerRetirementBarrier {
        await session.beginProducerRetirement(
            lease,
            acknowledgeLifecycle: acknowledgeLifecycle,
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
    }

    func waitForProducerCancellation() async {
        let stream = AsyncStream<Void> { _ in }
        for await _ in stream {}
    }

    func runBufferedContentProducer(
        _ body: BufferedContentBody,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws -> BufferedContentDeliveryDisposition {
        var offsetBytes = 0
        while offsetBytes < body.data.count {
            guard !Task.isCancelled else { return .cancelled }
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return .cancelled }
            let endOffset = min(
                offsetBytes + BridgeProductWireContract.maximumContentDataPayloadBytes,
                body.data.count
            )
            let chunkOffsetBytes = offsetBytes
            let payload = body.data.subdata(in: offsetBytes..<endOffset)
            let result = try await session.enqueueContentFrame(
                for: lease,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                build: { sequence in
                    .content(
                        .init(
                            header: try .data(
                                contentSequence: sequence,
                                offsetBytes: chunkOffsetBytes
                            ),
                            payload: payload
                        )
                    )
                },
                overflowReset: { sequence in
                    .content(
                        .init(
                            header: try .reset(
                                contentSequence: sequence,
                                reason: .producerOverflow
                            ),
                            payload: Data()
                        )
                    )
                }
            )
            guard case .enqueued = result else { return .deliveryFailed }
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return .cancelled }
            offsetBytes = endOffset
        }
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return .cancelled }
        let terminalResult = try await session.enqueueTerminalContentFrame(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            build: { sequence in
                .content(
                    .init(
                        header: try .end(
                            contentSequence: sequence,
                            endOfSource: body.endOfSource,
                            observedByteLength: body.data.count,
                            observedSha256: body.sha256
                        ),
                        payload: Data()
                    )
                )
            }
        )
        guard case .enqueued = terminalResult else { return .deliveryFailed }
        return .complete
    }
}
