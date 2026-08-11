import AgentStudioCore
import AgentStudioInfrastructure
import CryptoKit
import Foundation

struct BridgeProductReviewComparisonTargetsQueryCapture: Sendable {
    let descriptor: BridgeProductReviewComparisonTargetsContentDescriptor
    let body: Data
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
}

@MainActor
final class BridgeReviewComparisonTargetProjection {
    private(set) var currentTarget: WorkspaceReviewContributionTarget?

    init(state: BridgePaneState) {
        update(state: state)
    }

    func update(state: BridgePaneState) {
        guard case .workspace(_, let baseline) = state.source else {
            currentTarget = nil
            return
        }
        currentTarget = baseline?.contributionTarget
    }
}

enum BridgePaneProductComparisonTargetQuerySource {
    static func makeQuery(
        reviewSourceProvider: any BridgeReviewSourceProvider,
        targetProjection: BridgeReviewComparisonTargetProjection,
        refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
    ) -> @Sendable () async -> BridgeProductReviewComparisonTargetsQueryCapture? {
        {
            guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else {
                return nil
            }
            let currentTarget = await MainActor.run { targetProjection.currentTarget }
            let capturedAt = Int64(Date().timeIntervalSince1970 * 1000)
            let recencyMilliseconds =
                Int64(
                    AppPolicies.Bridge.reviewComparisonTargetRecencyWindow.components.seconds
                ) * 1000
            let request = BridgeReviewComparisonTargetsCaptureRequest(
                currentTarget: currentTarget,
                capturedAtUnixMilliseconds: capturedAt,
                cutoffUnixMilliseconds: max(0, capturedAt - recencyMilliseconds),
                maximumRows: AppPolicies.Bridge.reviewComparisonTargetMaximumRows
            )
            guard let capture = try? await reviewSourceProvider.captureReviewComparisonTargets(request) else {
                return nil
            }
            return makeCapture(
                capture,
                maximumEncodedBytes: AppPolicies.Bridge.reviewComparisonTargetMaximumEncodedBytes,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        }
    }

    static func makeCapture(
        _ capture: BridgeReviewComparisonTargetsCapture,
        maximumEncodedBytes: Int,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> BridgeProductReviewComparisonTargetsQueryCapture? {
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
            return makeQueryCapture(
                body: completeBody,
                capture: capture,
                foregroundWorkAdmission: foregroundWorkAdmission
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
        return makeQueryCapture(
            body: finalBody,
            capture: capture,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
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

    private static func makeQueryCapture(
        body: Data,
        capture: BridgeReviewComparisonTargetsCapture,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> BridgeProductReviewComparisonTargetsQueryCapture? {
        let digest = SHA256.hash(data: body)
            .map { String(format: "%02x", $0) }
            .joined()
        guard
            let descriptor = try? BridgeProductReviewComparisonTargetsContentDescriptor(
                capturedAtUnixMilliseconds: capture.capturedAtUnixMilliseconds,
                cutoffUnixMilliseconds: capture.cutoffUnixMilliseconds,
                declaredByteLength: body.count,
                descriptorId: UUIDv7.generate().uuidString,
                expectedSha256: digest,
                maximumBytes: body.count
            )
        else { return nil }
        return BridgeProductReviewComparisonTargetsQueryCapture(
            descriptor: descriptor,
            body: body,
            foregroundWorkAdmission: foregroundWorkAdmission
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
