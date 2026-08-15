import AgentStudioCore
import AgentStudioInfrastructure
import CryptoKit
import Foundation

struct BridgeReviewComparisonTargetProducedCatalog: Sendable {
    let body: Data
    let sha256: String
    let rowCount: Int?
    let isTruncated: Bool?

    init(
        body: Data,
        sha256: String,
        rowCount: Int? = nil,
        isTruncated: Bool? = nil
    ) {
        self.body = body
        self.sha256 = sha256
        self.rowCount = rowCount
        self.isTruncated = isTruncated
    }
}

protocol BridgeReviewComparisonTargetCatalogProducing: Sendable {
    func produceComparisonTargetCatalog(
        for reservation: BridgeProductReviewComparisonTargetsReservation
    ) async throws -> BridgeReviewComparisonTargetProducedCatalog
}

enum BridgeReviewComparisonTargetCatalogProducerError: Error {
    case unavailable
}

actor BridgeReviewComparisonTargetCatalogProducer: BridgeReviewComparisonTargetCatalogProducing {
    private let reviewSourceProvider: any BridgeReviewSourceProvider
    private let traceRecorder: (any BridgeReviewComparisonTargetCatalogTraceRecording)?

    init(
        reviewSourceProvider: any BridgeReviewSourceProvider,
        traceRecorder: (any BridgeReviewComparisonTargetCatalogTraceRecording)? = nil
    ) {
        self.reviewSourceProvider = reviewSourceProvider
        self.traceRecorder = traceRecorder
    }

    func produceComparisonTargetCatalog(
        for reservation: BridgeProductReviewComparisonTargetsReservation
    ) async throws -> BridgeReviewComparisonTargetProducedCatalog {
        let capturedAtUnixMilliseconds = Int64(Date().timeIntervalSince1970 * 1000)
        let recencyMilliseconds =
            Int64(
                AppPolicies.Bridge.reviewComparisonTargetRecencyWindow.components.seconds
            ) * 1000
        let captureStartedAt = ContinuousClock.now
        let capture: BridgeReviewComparisonTargetsCapture
        do {
            capture = try await reviewSourceProvider.captureReviewComparisonTargets(
                BridgeReviewComparisonTargetsCaptureRequest(
                    currentTarget: reservation.currentTarget,
                    capturedAtUnixMilliseconds: capturedAtUnixMilliseconds,
                    cutoffUnixMilliseconds: max(
                        0,
                        capturedAtUnixMilliseconds - recencyMilliseconds
                    ),
                    maximumRows: AppPolicies.Bridge.reviewComparisonTargetMaximumRows
                )
            )
            try Task.checkCancellation()
            recordStage(
                .scheduledCapture,
                outcome: .success,
                reservation: reservation,
                startedAt: captureStartedAt
            )
        } catch is CancellationError {
            recordStage(
                .scheduledCapture,
                outcome: .cancelled,
                reservation: reservation,
                startedAt: captureStartedAt
            )
            throw CancellationError()
        } catch {
            recordStage(
                .scheduledCapture,
                outcome: .failed,
                reservation: reservation,
                startedAt: captureStartedAt
            )
            throw error
        }
        let encodeStartedAt = ContinuousClock.now
        guard
            let producedCatalog = Self.produceCatalog(
                capture,
                maximumEncodedBytes: reservation.descriptor.maximumBytes
            )
        else {
            recordEncodeStage(
                outcome: .failed,
                reservation: reservation,
                capture: capture,
                producedCatalog: nil,
                startedAt: encodeStartedAt
            )
            throw BridgeReviewComparisonTargetCatalogProducerError.unavailable
        }
        recordEncodeStage(
            outcome: .success,
            reservation: reservation,
            capture: capture,
            producedCatalog: producedCatalog,
            startedAt: encodeStartedAt
        )
        return producedCatalog
    }

    static func produceCatalog(
        _ capture: BridgeReviewComparisonTargetsCapture,
        maximumEncodedBytes: Int
    ) -> BridgeReviewComparisonTargetProducedCatalog? {
        guard maximumEncodedBytes > 0 else { return nil }
        let preservedReferences = Set(
            [capture.defaultTarget, capture.currentTarget]
                .compactMap { $0.map(canonicalReferenceName) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let completeCatalog = catalog(capture: capture, branches: capture.branches)
        guard let completeBody = try? encoder.encode(completeCatalog) else { return nil }
        if completeBody.count <= maximumEncodedBytes {
            return producedCatalog(
                body: completeBody,
                rowCount: capture.branches.count,
                isTruncated: capture.isTruncated
            )
        }

        let truncatedCatalog = catalog(
            capture: capture,
            branches: capture.branches,
            isTruncated: true
        )
        guard
            let fullTruncatedBody = capture.isTruncated
                ? completeBody
                : try? encoder.encode(truncatedCatalog)
        else { return nil }
        var measuredByteCount = fullTruncatedBody.count
        var retainedBranchCount = capture.branches.count
        var retainedBranches = Array(repeating: true, count: retainedBranchCount)

        for index in capture.branches.indices.reversed()
        where measuredByteCount > maximumEncodedBytes || retainedBranchCount == capture.branches.count {
            let branch = capture.branches[index]
            guard !preservedReferences.contains(canonicalReferenceName(branch)) else { continue }
            guard let encodedArray = try? encoder.encode([branch]), encodedArray.count >= 2 else {
                return nil
            }
            let encodedBranchByteCount = encodedArray.count - 2
            let removedCommaByteCount = retainedBranchCount > 1 ? 1 : 0
            measuredByteCount -= encodedBranchByteCount + removedCommaByteCount
            retainedBranches[index] = false
            retainedBranchCount -= 1
        }

        guard measuredByteCount <= maximumEncodedBytes else { return nil }
        let branches = capture.branches.enumerated().compactMap { index, branch in
            retainedBranches[index] ? branch : nil
        }
        guard branches.count < capture.branches.count else { return nil }
        let finalCatalog = catalog(capture: capture, branches: branches, isTruncated: true)
        guard
            let finalBody = try? encoder.encode(finalCatalog),
            finalBody.count == measuredByteCount,
            finalBody.count <= maximumEncodedBytes
        else { return nil }
        return producedCatalog(body: finalBody, rowCount: branches.count, isTruncated: true)
    }

    private static func catalog(
        capture: BridgeReviewComparisonTargetsCapture,
        branches: [BridgeReviewComparisonBranchTarget],
        isTruncated: Bool? = nil
    ) -> BridgeReviewComparisonTargetCatalog {
        BridgeReviewComparisonTargetCatalog(
            capturedAtUnixMilliseconds: capture.capturedAtUnixMilliseconds,
            cutoffUnixMilliseconds: capture.cutoffUnixMilliseconds,
            isTruncated: isTruncated ?? capture.isTruncated,
            defaultTarget: capture.defaultTarget,
            currentTarget: capture.currentTarget,
            branches: branches
        )
    }

    private static func producedCatalog(
        body: Data,
        rowCount: Int,
        isTruncated: Bool
    ) -> BridgeReviewComparisonTargetProducedCatalog {
        let digest = SHA256.hash(data: body)
            .map { String(format: "%02x", $0) }
            .joined()
        return BridgeReviewComparisonTargetProducedCatalog(
            body: body,
            sha256: digest,
            rowCount: rowCount,
            isTruncated: isTruncated
        )
    }

    private func recordStage(
        _ stage: BridgeReviewComparisonTargetCatalogTraceEvent.Stage,
        outcome: BridgeReviewComparisonTargetCatalogTraceEvent.Outcome,
        reservation: BridgeProductReviewComparisonTargetsReservation,
        startedAt: ContinuousClock.Instant
    ) {
        traceRecorder?.submit(
            BridgeReviewComparisonTargetCatalogTraceEvent(
                stage: stage,
                outcome: outcome,
                queryRequestSequence: reservation.queryRequestSequence,
                durationMilliseconds: BridgeReviewComparisonTargetCatalogTraceEvent.milliseconds(
                    from: startedAt.duration(to: ContinuousClock.now)
                ),
                reservationAgeMilliseconds: nil,
                inputRowCount: nil,
                outputRowCount: nil,
                observedByteCount: nil,
                isTruncated: nil
            )
        )
    }

    private func recordEncodeStage(
        outcome: BridgeReviewComparisonTargetCatalogTraceEvent.Outcome,
        reservation: BridgeProductReviewComparisonTargetsReservation,
        capture: BridgeReviewComparisonTargetsCapture,
        producedCatalog: BridgeReviewComparisonTargetProducedCatalog?,
        startedAt: ContinuousClock.Instant
    ) {
        traceRecorder?.submit(
            BridgeReviewComparisonTargetCatalogTraceEvent(
                stage: .encode,
                outcome: outcome,
                queryRequestSequence: reservation.queryRequestSequence,
                durationMilliseconds: BridgeReviewComparisonTargetCatalogTraceEvent.milliseconds(
                    from: startedAt.duration(to: ContinuousClock.now)
                ),
                reservationAgeMilliseconds: nil,
                inputRowCount: capture.branches.count,
                outputRowCount: producedCatalog?.rowCount,
                observedByteCount: producedCatalog?.body.count,
                isTruncated: producedCatalog?.isTruncated
            )
        )
    }

    private static func canonicalReferenceName(
        _ target: BridgeReviewComparisonBranchTarget
    ) -> String {
        switch target {
        case .local(let branchName, _):
            return "refs/heads/\(branchName)"
        case .remoteTracking(let remoteName, let branchName, _):
            return "refs/remotes/\(remoteName)/\(branchName)"
        }
    }
}

struct BridgeUnavailableComparisonTargetCatalogProducer:
    BridgeReviewComparisonTargetCatalogProducing
{
    func produceComparisonTargetCatalog(
        for reservation: BridgeProductReviewComparisonTargetsReservation
    ) async throws -> BridgeReviewComparisonTargetProducedCatalog {
        _ = reservation
        throw BridgeReviewComparisonTargetCatalogProducerError.unavailable
    }
}
