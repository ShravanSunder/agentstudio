import AgentStudioCore
import AgentStudioInfrastructure
import CryptoKit
import Foundation

struct BridgeProductReviewComparisonTargetsQueryCapture: Sendable {
    let descriptor: BridgeProductReviewComparisonTargetsContentDescriptor
    let body: Data
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
        targetProjection: BridgeReviewComparisonTargetProjection
    ) -> @Sendable () async -> BridgeProductReviewComparisonTargetsQueryCapture? {
        {
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
                maximumEncodedBytes: AppPolicies.Bridge.reviewComparisonTargetMaximumEncodedBytes
            )
        }
    }

    static func makeCapture(
        _ capture: BridgeReviewComparisonTargetsCapture,
        maximumEncodedBytes: Int
    ) -> BridgeProductReviewComparisonTargetsQueryCapture? {
        guard maximumEncodedBytes > 0 else { return nil }
        let preservedReferences = Set(
            [capture.defaultTarget, capture.currentTarget]
                .compactMap { $0.map(canonicalReferenceName) }
        )
        var branches = capture.branches
        var isTruncated = capture.isTruncated
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        while true {
            let catalog = BridgeReviewComparisonTargetCatalog(
                capturedAtUnixMilliseconds: capture.capturedAtUnixMilliseconds,
                cutoffUnixMilliseconds: capture.cutoffUnixMilliseconds,
                isTruncated: isTruncated,
                defaultTarget: capture.defaultTarget,
                currentTarget: capture.currentTarget,
                branches: branches
            )
            guard let body = try? encoder.encode(catalog) else { return nil }
            if body.count <= maximumEncodedBytes {
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
                        maximumBytes: maximumEncodedBytes
                    )
                else { return nil }
                return BridgeProductReviewComparisonTargetsQueryCapture(
                    descriptor: descriptor,
                    body: body
                )
            }

            guard
                let index = branches.lastIndex(where: {
                    !preservedReferences.contains(canonicalReferenceName($0))
                })
            else { return nil }
            branches.remove(at: index)
            isTruncated = true
        }
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
