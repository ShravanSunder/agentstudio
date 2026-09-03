import AgentStudioCore
import AgentStudioGit
import AgentStudioInfrastructure
import Foundation

enum BridgeReviewRefreshPromotionReason: String, Codable, Equatable, Sendable {
    case commits
    case files
    case lines
    case unknown
}

enum BridgeReviewPreDeliveryPresentationClass: Codable, Equatable, Sendable {
    case ordinary
    case promoted(reason: BridgeReviewRefreshPromotionReason)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case reason
    }

    private enum Kind: String, Codable {
        case ordinary
        case promoted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ordinary:
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.kind])
            self = .ordinary
        case .promoted:
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.kind, .reason])
            self = .promoted(
                reason: try container.decode(BridgeReviewRefreshPromotionReason.self, forKey: .reason)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ordinary:
            try container.encode(Kind.ordinary, forKey: .kind)
        case .promoted(let reason):
            try container.encode(Kind.promoted, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }

    private static func rejectUnknownKeys(
        from decoder: Decoder,
        allowedKeys: Set<CodingKeys>
    ) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(allowedKeys.map(\.rawValue)),
            contract: "Review refresh presentation class"
        )
    }
}

struct BridgeReviewRefreshImpact: Equatable, Sendable {
    let preDeliveryPresentationClass: BridgeReviewPreDeliveryPresentationClass
    let newlyImportedCommitCount: Int?
    let affectedFileCount: Int?
    let addedLineCount: Int?
    let deletedLineCount: Int?
    let affectedStableFileIdentities: [String]

    static let initial = exact(
        newlyImportedCommitCount: 0,
        affectedFileCount: 0,
        addedLineCount: 0,
        deletedLineCount: 0,
        affectedStableFileIdentities: []
    )

    static func exact(
        newlyImportedCommitCount: Int,
        affectedFileCount: Int,
        addedLineCount: Int,
        deletedLineCount: Int,
        affectedStableFileIdentities: [String]
    ) -> Self {
        let presentationClass: BridgeReviewPreDeliveryPresentationClass
        if newlyImportedCommitCount >= AppPolicies.Bridge.reviewRefreshPromotionImportedCommitCount {
            presentationClass = .promoted(reason: .commits)
        } else if affectedFileCount >= AppPolicies.Bridge.reviewRefreshPromotionAffectedFileCount {
            presentationClass = .promoted(reason: .files)
        } else if addedLineCount.addingReportingOverflow(deletedLineCount).overflow
            || addedLineCount + deletedLineCount >= AppPolicies.Bridge.reviewRefreshPromotionChangedLineCount
        {
            presentationClass = .promoted(reason: .lines)
        } else {
            presentationClass = .ordinary
        }
        return Self(
            preDeliveryPresentationClass: presentationClass,
            newlyImportedCommitCount: newlyImportedCommitCount,
            affectedFileCount: affectedFileCount,
            addedLineCount: addedLineCount,
            deletedLineCount: deletedLineCount,
            affectedStableFileIdentities: Self.normalizedIdentities(affectedStableFileIdentities)
        )
    }

    static func unknown(
        displayedPackage _: BridgeReviewPackage?,
        candidatePackage _: BridgeReviewPackage
    ) -> Self {
        Self(
            preDeliveryPresentationClass: .promoted(reason: .unknown),
            newlyImportedCommitCount: nil,
            affectedFileCount: nil,
            addedLineCount: nil,
            deletedLineCount: nil,
            affectedStableFileIdentities: []
        )
    }

    private static func normalizedIdentities(_ identities: [String]) -> [String] {
        Array(Set(identities)).sorted()
    }
}

protocol BridgeReviewRefreshImpactDataClient: Sendable {
    var repositoryPath: URL { get }

    func countCommitRange(
        _ request: GitCommitRangeCountRequest,
        candidateGeneration: BridgeReviewGeneration
    ) async throws -> GitCommitRangeCount
    func summarizeDiffImpact(
        _ request: GitDiffImpactSummaryRequest,
        candidateGeneration: BridgeReviewGeneration
    ) async throws -> GitDiffImpactSummary
}

protocol BridgeReviewRefreshImpactSourceProvider: Sendable {
    func measureRefreshImpact(
        displayedPackage: BridgeReviewPackage,
        candidatePackage: BridgeReviewPackage,
        candidateGeneration: BridgeReviewGeneration
    ) async throws -> BridgeReviewRefreshImpact
}

struct BridgeReviewRefreshImpactProvider: Sendable {
    private struct SemanticSourceScope: Equatable, Sendable {
        let repoId: UUID
        let worktreeId: UUID
        let queryKind: BridgeReviewQuery.Kind
        let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
        let pathScope: [String]
        let fileTarget: String?
        let viewFilter: BridgeViewFilter
        let grouping: BridgeChangeGrouping
        let provenanceFilter: BridgeProvenanceFilter
        let symbolicTarget: WorkspaceReviewContributionTarget

        init(query: BridgeReviewQuery, symbolicTarget: WorkspaceReviewContributionTarget) {
            repoId = query.repoId
            worktreeId = query.worktreeId
            queryKind = query.queryKind
            comparisonSemantics = query.comparisonSemantics
            pathScope = query.pathScope
            fileTarget = query.fileTarget
            viewFilter = query.viewFilter
            grouping = query.grouping
            provenanceFilter = query.provenanceFilter
            self.symbolicTarget = symbolicTarget
        }
    }

    private struct ContributionSource: Equatable, Sendable {
        let semanticScope: SemanticSourceScope
        let reviewedHeadOID: String
    }

    private let dataClient: any BridgeReviewRefreshImpactDataClient

    init(dataClient: any BridgeReviewRefreshImpactDataClient) {
        self.dataClient = dataClient
    }

    func measure(
        displayedPackage: BridgeReviewPackage,
        candidatePackage: BridgeReviewPackage,
        candidateGeneration: BridgeReviewGeneration
    ) async throws -> BridgeReviewRefreshImpact {
        guard let displayedSource = Self.contributionSource(from: displayedPackage),
            let candidateSource = Self.contributionSource(from: candidatePackage),
            displayedSource.semanticScope == candidateSource.semanticScope
        else {
            return .unknown(displayedPackage: displayedPackage, candidatePackage: candidatePackage)
        }

        do {
            async let commitRangeCount = dataClient.countCommitRange(
                GitCommitRangeCountRequest(
                    repositoryPath: dataClient.repositoryPath,
                    base: .named(displayedSource.reviewedHeadOID),
                    candidate: .named(candidateSource.reviewedHeadOID),
                    maximumCount: AppPolicies.Bridge.reviewRefreshPromotionImportedCommitCount,
                    maximumTraversalCount: AppPolicies.Bridge
                        .reviewRefreshImpactMaximumCommitTraversalCount
                ),
                candidateGeneration: candidateGeneration
            )
            async let diffImpact = dataClient.summarizeDiffImpact(
                GitDiffImpactSummaryRequest(
                    repositoryPath: dataClient.repositoryPath,
                    base: .commit(displayedSource.reviewedHeadOID),
                    compare: .commit(candidateSource.reviewedHeadOID),
                    maximumChangedFileCount: AppPolicies.Bridge
                        .reviewRefreshPromotionAffectedFileCount,
                    maximumChangedLineCount: AppPolicies.Bridge
                        .reviewRefreshPromotionChangedLineCount,
                    maximumDiffableBlobByteCount: AppPolicies.Bridge
                        .reviewRefreshImpactMaximumDiffableBlobByteCount
                ),
                candidateGeneration: candidateGeneration
            )
            let (commitCountResult, diffSummary) = try await (commitRangeCount, diffImpact)
            guard let commitCount = Self.boundedCommitCount(commitCountResult) else {
                return .unknown(displayedPackage: displayedPackage, candidatePackage: candidatePackage)
            }
            guard diffSummary.pathsAreComplete,
                case .exact(let affectedFileCount) = diffSummary.changedFileCount,
                diffSummary.changedLineCount != .indeterminate,
                let addedLineCount = diffSummary.addedLineCount,
                let deletedLineCount = diffSummary.deletedLineCount
            else {
                return .unknown(displayedPackage: displayedPackage, candidatePackage: candidatePackage)
            }
            guard
                let affectedIdentities = Self.affectedStableFileIdentities(
                    changedPaths: diffSummary.changedPaths,
                    displayedPackage: displayedPackage,
                    candidatePackage: candidatePackage
                )
            else {
                return .unknown(displayedPackage: displayedPackage, candidatePackage: candidatePackage)
            }
            return .exact(
                newlyImportedCommitCount: commitCount,
                affectedFileCount: affectedFileCount,
                addedLineCount: addedLineCount,
                deletedLineCount: deletedLineCount,
                affectedStableFileIdentities: affectedIdentities
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unknown(displayedPackage: displayedPackage, candidatePackage: candidatePackage)
        }
    }

    private static func contributionSource(from package: BridgeReviewPackage) -> ContributionSource? {
        guard case .contribution(let origin) = package.comparisonOrigin else { return nil }
        return ContributionSource(
            semanticScope: SemanticSourceScope(
                query: package.query,
                symbolicTarget: origin.symbolicTarget
            ),
            reviewedHeadOID: origin.reviewedHeadOID
        )
    }

    /// Returns either the exact count below the cap or the conservative lower
    /// bound reported when the bounded walk reaches the promotion threshold.
    private static func boundedCommitCount(_ count: GitCommitRangeCount) -> Int? {
        switch count {
        case .exact(let exactCount), .atLeastLimit(let exactCount):
            exactCount
        case .traversalLimitReached, .unrelated:
            nil
        }
    }

    private static func affectedStableFileIdentities(
        changedPaths: [GitDiffImpactPath],
        displayedPackage: BridgeReviewPackage,
        candidatePackage: BridgeReviewPackage
    ) -> [String]? {
        var stableIdentitiesByPath: [String: Set<String>] = [:]
        for package in [displayedPackage, candidatePackage] {
            for item in package.itemsById.values {
                for path in [item.basePath, item.headPath].compactMap({ $0 }) {
                    stableIdentitiesByPath[path, default: []].insert(item.itemId)
                }
            }
        }
        var affectedIdentities: Set<String> = []
        for changedPath in changedPaths {
            let fileIdentities = [changedPath.currentPath, changedPath.previousPath]
                .compactMap { $0 }
                .reduce(into: Set<String>()) { identities, path in
                    identities.formUnion(stableIdentitiesByPath[path] ?? [])
                }
            guard !fileIdentities.isEmpty else { return nil }
            affectedIdentities.formUnion(fileIdentities)
        }
        return affectedIdentities.sorted()
    }
}

enum BridgeReviewRefreshImpactCodingKey: String, CodingKey, CaseIterable {
    case addedLineCount
    case affectedFileCount
    case affectedStableFileIdentities
    case deletedLineCount
    case newlyImportedCommitCount
    case preDeliveryPresentationClass
}

enum BridgeReviewRefreshImpactWireContract {
    static let codingKeyNames = Set(BridgeReviewRefreshImpactCodingKey.allCases.map(\.rawValue))

    static func containsAny(in decoder: Decoder) throws -> Bool {
        let container = try decoder.container(keyedBy: BridgeReviewRefreshImpactCodingKey.self)
        return BridgeReviewRefreshImpactCodingKey.allCases.contains { container.contains($0) }
    }

    static func decodeRequired(from decoder: Decoder) throws -> BridgeReviewRefreshImpact {
        let container = try decoder.container(keyedBy: BridgeReviewRefreshImpactCodingKey.self)
        guard BridgeReviewRefreshImpactCodingKey.allCases.allSatisfy(container.contains) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review refresh impact must carry its complete field set",
                codingPath: decoder.codingPath
            )
        }
        let impact = BridgeReviewRefreshImpact(
            preDeliveryPresentationClass: try container.decode(
                BridgeReviewPreDeliveryPresentationClass.self,
                forKey: .preDeliveryPresentationClass
            ),
            newlyImportedCommitCount: try container.decodeIfPresent(Int.self, forKey: .newlyImportedCommitCount),
            affectedFileCount: try container.decodeIfPresent(Int.self, forKey: .affectedFileCount),
            addedLineCount: try container.decodeIfPresent(Int.self, forKey: .addedLineCount),
            deletedLineCount: try container.decodeIfPresent(Int.self, forKey: .deletedLineCount),
            affectedStableFileIdentities: try container.decode([String].self, forKey: .affectedStableFileIdentities)
        )
        try validate(impact, codingPath: decoder.codingPath)
        return impact
    }

    static func encode(_ impact: BridgeReviewRefreshImpact, to encoder: Encoder) throws {
        try validate(impact, codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: BridgeReviewRefreshImpactCodingKey.self)
        try container.encode(impact.preDeliveryPresentationClass, forKey: .preDeliveryPresentationClass)
        try container.encode(impact.newlyImportedCommitCount, forKey: .newlyImportedCommitCount)
        try container.encode(impact.affectedFileCount, forKey: .affectedFileCount)
        try container.encode(impact.addedLineCount, forKey: .addedLineCount)
        try container.encode(impact.deletedLineCount, forKey: .deletedLineCount)
        try container.encode(impact.affectedStableFileIdentities, forKey: .affectedStableFileIdentities)
    }

    static func validate(
        _ impact: BridgeReviewRefreshImpact,
        codingPath: [any CodingKey]
    ) throws {
        let counts = [
            impact.newlyImportedCommitCount,
            impact.affectedFileCount,
            impact.addedLineCount,
            impact.deletedLineCount,
        ]
        let requiresUnknownCounts: Bool
        switch impact.preDeliveryPresentationClass {
        case .ordinary, .promoted(reason: .commits), .promoted(reason: .files), .promoted(reason: .lines):
            requiresUnknownCounts = false
        case .promoted(reason: .unknown):
            requiresUnknownCounts = true
        }
        guard requiresUnknownCounts ? counts.allSatisfy({ $0 == nil }) : counts.allSatisfy({ $0 != nil }) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review refresh impact counts do not match its presentation class",
                codingPath: codingPath
            )
        }
        for count in counts.compactMap({ $0 }) {
            try BridgeProductContractDecoding.validateNonnegative(
                count,
                name: "Review refresh impact count",
                codingPath: codingPath
            )
        }
        try BridgeProductContractDecoding.validateCollectionCount(
            impact.affectedStableFileIdentities.count,
            maximum: BridgeProductReviewMetadataLimits.maximumWindowEntryCount,
            name: "affectedStableFileIdentities",
            codingPath: codingPath
        )
        for identity in impact.affectedStableFileIdentities {
            try BridgeProductContractDecoding.validateIdentifier(identity, codingPath: codingPath)
        }
        guard Set(impact.affectedStableFileIdentities).count == impact.affectedStableFileIdentities.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review affected stable file identities must be unique",
                codingPath: codingPath
            )
        }
    }
}
