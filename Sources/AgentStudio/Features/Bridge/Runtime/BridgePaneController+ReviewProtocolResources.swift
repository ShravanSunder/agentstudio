import Foundation

@MainActor
extension BridgePaneController {
    /// Emits the review package load as scheduler jobs on the shared metadata
    /// lane scheduler. Reset, snapshot, and delta ride the foreground lane in
    /// FIFO order; startup metadata windows ride the speculative lane so
    /// later metadata interest can jump ahead of them (spec:
    /// review-protocol.md §2.1 — review contributes no idle-lane jobs).
    /// Sequences are consumed inside the serialized drain, so review delivery
    /// order equals sequence order by construction.
    func commitReviewPackageLoad(
        _ load: BridgeReviewPackageLoadData,
        traceContext: BridgeTraceContext?
    ) async {
        let generation = load.package.reviewGeneration.rawValue
        let package = load.package
        await enqueueReviewProtocolFrameJob(
            lane: .foreground,
            generation: generation,
            traceContext: traceContext
        ) { [weak self] sequence in
            guard let self else { return nil }
            return .snapshot(
                try self.makeReviewProtocolSnapshotFrame(package: package, sequence: sequence)
            )
        }
        if let delta = load.delta {
            await enqueueReviewProtocolFrameJob(
                lane: .foreground,
                generation: generation,
                traceContext: traceContext
            ) { [weak self] sequence in
                guard let self else { return nil }
                return .delta(
                    try self.makeReviewProtocolDeltaFrame(
                        package: package,
                        delta: delta,
                        sequence: sequence
                    )
                )
            }
        }
        for itemIds in Self.reviewStartupMetadataWindowItemIdChunks(package: package) {
            await enqueueReviewProtocolFrameJob(
                lane: .speculative,
                generation: generation,
                traceContext: traceContext
            ) { [weak self] sequence in
                guard let self else { return nil }
                return .metadataWindow(
                    try await self.makeReviewProtocolMetadataWindowFrame(
                        package: package,
                        itemIds: itemIds,
                        sequence: sequence
                    )
                )
            }
        }
        paneState.diff.setPackageMetadata(load.package)
        paneState.diff.setPackageDelta(load.delta)
        paneState.diff.setStatus(.ready)
    }

    func deliverReviewProtocolErrorFrame(
        streamId: String,
        generation: Int,
        message: String,
        traceContext: BridgeTraceContext?
    ) async {
        let pushNonce = pushNonce
        await enqueueReviewProtocolEncodedFrameJob(
            lane: .foreground,
            generation: generation
        ) { sequence in
            try await PreEncodedIntakeFrame.makeEncodedPayload(
                metadata: BridgeIntakeFrameMetadata(
                    kind: .error,
                    streamId: streamId,
                    generation: generation,
                    sequence: sequence,
                    message: message
                ),
                payload: Data(),
                traceContext: traceContext,
                pushNonce: pushNonce
            )
        }
    }

    /// Enqueues one review protocol frame emission. The build closure runs
    /// inside the serialized scheduler drain with the dispatched sequence.
    func enqueueReviewProtocolFrameJob(
        lane: BridgeDemandLane,
        generation: Int,
        traceContext: BridgeTraceContext?,
        buildFrame: @escaping @MainActor (Int) async throws -> BridgeReviewProtocolFrame?
    ) async {
        await enqueueReviewProtocolEncodedFrameJob(lane: lane, generation: generation) { [weak self] sequence in
            guard let self, let frame = try await buildFrame(sequence) else { return nil }
            return try await PreEncodedIntakeFrame.make(
                metadata: Self.reviewIntakeFrameMetadata(for: frame),
                payload: frame,
                traceContext: traceContext,
                pushNonce: self.pushNonce
            )
        }
    }

    func enqueueReviewProtocolEncodedFrameJob(
        lane: BridgeDemandLane,
        generation: Int,
        encodeFrame: @escaping @MainActor (Int) async throws -> PreEncodedIntakeFrame?
    ) async {
        await worktreeFileMetadataScheduler.enqueue(
            BridgeMetadataLaneJob(
                protocolId: "review",
                generation: generation,
                lane: lane
            ) { [weak self] in
                guard let self else { return true }
                return await self.deliverReviewProtocolEncodedFrameJob(
                    generation: generation,
                    encodeFrame: encodeFrame
                )
            }
        )
    }

    /// Runs inside a serialized scheduler job: consumes the next review
    /// sequence, encodes, and delivers. A failed delivery rolls the sequence
    /// back so the scheduler's retained-job retry redelivers with the same
    /// sequence instead of leaving a gap. Build/encode errors consume no
    /// sequence and are reported as connection health errors because a retry
    /// cannot fix them.
    private func deliverReviewProtocolEncodedFrameJob(
        generation: Int,
        encodeFrame: @MainActor (Int) async throws -> PreEncodedIntakeFrame?
    ) async -> Bool {
        guard generation == nextReviewGeneration.rawValue else { return true }
        guard !shouldSuppressReviewProtocolProduction(generation: generation) else {
            await recordActiveViewerModeSuppression(
                suppressedProtocolId: "review",
                generation: generation,
                phase: "review_delivery"
            )
            return true
        }
        let sequence = consumeNextReviewProtocolSequence()
        do {
            guard let encodedFrame = try await encodeFrame(sequence) else {
                rollbackReviewProtocolSequence(from: sequence)
                return true
            }
            guard await deliverIntakeFrame(encodedFrame) else {
                rollbackReviewProtocolSequence(from: sequence)
                paneState.connection.setHealth(.error)
                return false
            }
            reviewProtocolSuppressedDrop = nil
            return true
        } catch {
            rollbackReviewProtocolSequence(from: sequence)
            paneState.connection.setHealth(.error)
            return true
        }
    }

    private func rollbackReviewProtocolSequence(from sequence: Int) {
        guard nextReviewProtocolSequence == sequence + 1 else { return }
        nextReviewProtocolSequence = sequence
    }

    private static func reviewIntakeFrameMetadata(
        for frame: BridgeReviewProtocolFrame
    ) -> BridgeIntakeFrameMetadata {
        switch frame {
        case .snapshot(let snapshot):
            BridgeIntakeFrameMetadata(
                kind: .snapshot,
                streamId: snapshot.streamId,
                generation: snapshot.generation,
                sequence: snapshot.sequence
            )
        case .metadataWindow(let metadataWindow):
            BridgeIntakeFrameMetadata(
                kind: .delta,
                streamId: metadataWindow.streamId,
                generation: metadataWindow.generation,
                sequence: metadataWindow.sequence
            )
        case .delta(let delta):
            BridgeIntakeFrameMetadata(
                kind: .delta,
                streamId: delta.streamId,
                generation: delta.generation,
                sequence: delta.sequence
            )
        case .invalidation(let invalidation):
            BridgeIntakeFrameMetadata(
                kind: .invalidate,
                streamId: invalidation.streamId,
                generation: invalidation.generation,
                sequence: invalidation.sequence
            )
        case .reset(let reset):
            BridgeIntakeFrameMetadata(
                kind: .reset,
                streamId: reset.streamId,
                generation: reset.generation,
                sequence: reset.sequence
            )
        }
    }
}
