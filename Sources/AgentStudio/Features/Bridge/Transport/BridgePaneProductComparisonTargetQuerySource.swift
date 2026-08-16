import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

struct BridgeProductReviewComparisonTargetsAuthorization: Sendable {
    let descriptor: BridgeProductReviewComparisonTargetsContentDescriptor
    let currentTarget: WorkspaceReviewContributionTarget?
}

struct BridgeProductReviewComparisonTargetsReservation: Sendable {
    let authorization: BridgeProductReviewComparisonTargetsAuthorization
    let issuedAt: ContinuousClock.Instant
    let paneSessionId: String
    let queryRequestSequence: Int
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceId: String

    var descriptor: BridgeProductReviewComparisonTargetsContentDescriptor {
        authorization.descriptor
    }

    var currentTarget: WorkspaceReviewContributionTarget? {
        authorization.currentTarget
    }

    init?(
        authorization: BridgeProductReviewComparisonTargetsAuthorization,
        issuing request: BridgeProductControlRequest
    ) {
        guard request.surface == .review,
            let workerDerivationEpoch = request.workerDerivationEpoch
        else { return nil }
        self.authorization = authorization
        self.issuedAt = ContinuousClock.now
        self.paneSessionId = request.paneSessionId
        self.queryRequestSequence = request.requestSequence
        self.wireVersion = request.correlation.wireVersion
        self.workerDerivationEpoch = workerDerivationEpoch
        self.workerInstanceId = request.workerInstanceId
    }

    func matches(_ request: BridgeProductReviewComparisonTargetsContentRequest) -> Bool {
        descriptor == request.descriptor
            && paneSessionId == request.paneSessionId
            && wireVersion == request.wireVersion
            && workerDerivationEpoch == request.workerDerivationEpoch
            && workerInstanceId == request.workerInstanceId
    }
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
    static func makeAuthorization(
        targetProjection: BridgeReviewComparisonTargetProjection,
        refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
    ) -> @Sendable () async -> BridgeProductReviewComparisonTargetsAuthorization? {
        {
            guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else {
                return nil
            }
            let currentTarget = await MainActor.run { targetProjection.currentTarget }
            guard
                let descriptor = try? BridgeProductReviewComparisonTargetsContentDescriptor(
                    descriptorId: UUIDv7.generate().uuidString,
                    maximumBytes: AppPolicies.Bridge.reviewComparisonTargetMaximumEncodedBytes
                )
            else { return nil }
            return foregroundWorkAdmission.withValidAdmission {
                BridgeProductReviewComparisonTargetsAuthorization(
                    descriptor: descriptor,
                    currentTarget: currentTarget
                )
            }
        }
    }
}
