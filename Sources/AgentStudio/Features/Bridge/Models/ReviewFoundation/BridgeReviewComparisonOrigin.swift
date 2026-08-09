import AgentStudioCore
import Foundation

package enum BridgeReviewComparisonOrigin: Codable, Equatable, Sendable {
    case contribution(BridgeReviewContributionOrigin)

    private enum Kind: String, Codable {
        case contribution
    }

    private enum EndpointRole: String, Codable {
        case contributionBase
        case capturedWorkingTree
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case baseRole
        case comparedRole
        case symbolicTarget
        case resolvedTargetOID
        case reviewedHeadOID
        case contributionBaseOID
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .contribution:
            try Self.requireKeys(
                Set(container.allKeys),
                equalTo: [
                    .kind, .baseRole, .comparedRole, .symbolicTarget,
                    .resolvedTargetOID, .reviewedHeadOID, .contributionBaseOID,
                ],
                decoder: decoder
            )
            try Self.requireRole(
                .contributionBase,
                forKey: .baseRole,
                in: container,
                decoder: decoder
            )
            try Self.requireRole(
                .capturedWorkingTree,
                forKey: .comparedRole,
                in: container,
                decoder: decoder
            )
            self = .contribution(
                BridgeReviewContributionOrigin(
                    symbolicTarget: try container.decode(
                        WorkspaceReviewContributionTarget.self,
                        forKey: .symbolicTarget
                    ),
                    resolvedTargetOID: try Self.nonemptyOID(
                        from: container,
                        forKey: .resolvedTargetOID,
                        decoder: decoder
                    ),
                    reviewedHeadOID: try Self.nonemptyOID(
                        from: container,
                        forKey: .reviewedHeadOID,
                        decoder: decoder
                    ),
                    contributionBaseOID: try Self.nonemptyOID(
                        from: container,
                        forKey: .contributionBaseOID,
                        decoder: decoder
                    )
                )
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .contribution(let origin):
            try Self.validateNonemptyOID(origin.resolvedTargetOID, encoder: encoder)
            try Self.validateNonemptyOID(origin.reviewedHeadOID, encoder: encoder)
            try Self.validateNonemptyOID(origin.contributionBaseOID, encoder: encoder)
            try container.encode(Kind.contribution, forKey: .kind)
            try container.encode(EndpointRole.contributionBase, forKey: .baseRole)
            try container.encode(EndpointRole.capturedWorkingTree, forKey: .comparedRole)
            try container.encode(origin.symbolicTarget, forKey: .symbolicTarget)
            try container.encode(origin.resolvedTargetOID, forKey: .resolvedTargetOID)
            try container.encode(origin.reviewedHeadOID, forKey: .reviewedHeadOID)
            try container.encode(origin.contributionBaseOID, forKey: .contributionBaseOID)
        }
    }

    private static func requireKeys(
        _ actualKeys: Set<CodingKeys>,
        equalTo expectedKeys: Set<CodingKeys>,
        decoder: Decoder
    ) throws {
        guard actualKeys == expectedKeys else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Comparison origin fields do not match its kind"
                )
            )
        }
    }

    private static func requireRole(
        _ expectedRole: EndpointRole,
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        decoder: Decoder
    ) throws {
        guard try container.decode(EndpointRole.self, forKey: key) == expectedRole else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Comparison endpoint role does not match its kind"
                )
            )
        }
    }

    private static func nonemptyOID(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        decoder: Decoder
    ) throws -> String {
        let value = try container.decode(String.self, forKey: key)
        guard !value.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Comparison origin OID must not be empty"
                )
            )
        }
        return value
    }

    private static func validateNonemptyOID(_ value: String, encoder: Encoder) throws {
        guard !value.isEmpty else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Comparison origin OID must not be empty"
                )
            )
        }
    }
}

package struct BridgeReviewContributionOrigin: Codable, Equatable, Sendable {
    package let symbolicTarget: WorkspaceReviewContributionTarget
    package let resolvedTargetOID: String
    package let reviewedHeadOID: String
    package let contributionBaseOID: String

    package init(
        symbolicTarget: WorkspaceReviewContributionTarget,
        resolvedTargetOID: String,
        reviewedHeadOID: String,
        contributionBaseOID: String
    ) {
        self.symbolicTarget = symbolicTarget
        self.resolvedTargetOID = resolvedTargetOID
        self.reviewedHeadOID = reviewedHeadOID
        self.contributionBaseOID = contributionBaseOID
    }
}

package struct BridgeContributionComparisonRequest: Equatable, Sendable {
    package let symbolicTarget: WorkspaceReviewContributionTarget
    package let baseEndpoint: BridgeSourceEndpoint
    package let headEndpoint: BridgeSourceEndpoint
    package let reviewGenerationValue: Int

    package init(
        symbolicTarget: WorkspaceReviewContributionTarget,
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        reviewGenerationValue: Int
    ) {
        self.symbolicTarget = symbolicTarget
        self.baseEndpoint = baseEndpoint
        self.headEndpoint = headEndpoint
        self.reviewGenerationValue = reviewGenerationValue
    }
}

package struct BridgeContributionComparisonCapture: Equatable, Sendable {
    package let resolvedTargetOID: String
    package let reviewedHeadOID: String
    package let contributionBaseOID: String
    package let comparison: BridgeEndpointComparison

    package init(
        resolvedTargetOID: String,
        reviewedHeadOID: String,
        contributionBaseOID: String,
        comparison: BridgeEndpointComparison
    ) {
        self.resolvedTargetOID = resolvedTargetOID
        self.reviewedHeadOID = reviewedHeadOID
        self.contributionBaseOID = contributionBaseOID
        self.comparison = comparison
    }
}

enum BridgeResolvedContributionRequestBuilder {
    static func build(
        request: BridgeReviewPipelineRequest,
        symbolicTarget: WorkspaceReviewContributionTarget,
        capture: BridgeContributionComparisonCapture,
        reviewedSubjectLabel: String?
    ) throws -> BridgeReviewPipelineRequest {
        guard capture.comparison.baseEndpoint.repoId == request.query.repoId,
            capture.comparison.headEndpoint.repoId == request.query.repoId,
            capture.comparison.baseEndpoint.worktreeId == request.query.worktreeId,
            capture.comparison.headEndpoint.worktreeId == request.query.worktreeId
        else {
            throw BridgeProviderFailure.providerFailed(
                message: "Prepared contribution endpoints do not match the requested repository and worktree"
            )
        }
        guard capture.comparison.baseEndpoint.kind == .gitRef,
            capture.comparison.headEndpoint.kind == .workingTree
        else {
            throw BridgeProviderFailure.providerFailed(
                message: "Prepared contribution requires contribution-base and working-tree endpoint roles"
            )
        }
        guard capture.comparison.baseEndpoint.endpointId == request.baseEndpoint.endpointId,
            capture.comparison.headEndpoint.endpointId == request.headEndpoint.endpointId
        else {
            throw BridgeProviderFailure.providerFailed(
                message: "Prepared contribution endpoint identities do not match the request"
            )
        }
        let query = BridgeReviewQuery(
            queryId: request.query.queryId,
            queryKind: request.query.queryKind,
            repoId: request.query.repoId,
            worktreeId: request.query.worktreeId,
            baseEndpointId: capture.comparison.baseEndpoint.endpointId,
            headEndpointId: capture.comparison.headEndpoint.endpointId,
            comparisonSemantics: .workingTreeDelta,
            pathScope: request.query.pathScope,
            fileTarget: request.query.fileTarget,
            viewFilter: request.query.viewFilter,
            grouping: request.query.grouping,
            provenanceFilter: request.query.provenanceFilter
        )
        return BridgeReviewPipelineRequest(
            packageId: request.packageId,
            query: query,
            baseEndpoint: capture.comparison.baseEndpoint,
            headEndpoint: capture.comparison.headEndpoint,
            checkpointIds: request.checkpointIds,
            reviewGeneration: request.reviewGeneration,
            generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds,
            preparedComparison: capture.comparison,
            comparisonOrigin: .contribution(
                BridgeReviewContributionOrigin(
                    symbolicTarget: symbolicTarget,
                    resolvedTargetOID: capture.resolvedTargetOID,
                    reviewedHeadOID: capture.reviewedHeadOID,
                    contributionBaseOID: capture.contributionBaseOID
                )
            ),
            reviewedSubjectLabel: reviewedSubjectLabel
        )
    }
}
