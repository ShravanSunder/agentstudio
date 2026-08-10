public enum IPCBridgeReviewComparisonBasis: String, Codable, Equatable, Sendable {
    case commonCommit
    case branchTip
}

public enum IPCBridgeReviewComparisonBaseRole: String, Codable, Equatable, Sendable {
    case commonCommit
    case selectedTarget
}

public struct IPCBridgeReviewContributionOrigin: Codable, Equatable, Sendable {
    public let symbolicTarget: IPCBridgeReviewComparisonTarget
    public let resolvedTargetOID: String
    public let reviewedHeadOID: String
    public let baseRole: IPCBridgeReviewComparisonBaseRole
    public let baseOID: String

    public init(
        symbolicTarget: IPCBridgeReviewComparisonTarget,
        resolvedTargetOID: String,
        reviewedHeadOID: String,
        baseRole: IPCBridgeReviewComparisonBaseRole,
        baseOID: String
    ) {
        self.symbolicTarget = symbolicTarget
        self.resolvedTargetOID = resolvedTargetOID
        self.reviewedHeadOID = reviewedHeadOID
        self.baseRole = baseRole
        self.baseOID = baseOID
    }
}

public enum IPCBridgeReviewComparisonTarget: Codable, Equatable, Sendable {
    case localDefaultBranch(branchName: String, basis: IPCBridgeReviewComparisonBasis)
    case originDefaultBranch(remoteName: String, branchName: String, basis: IPCBridgeReviewComparisonBasis)
    case branch(name: String, basis: IPCBridgeReviewComparisonBasis)
    case commit(oid: String)
    case ref(name: String, basis: IPCBridgeReviewComparisonBasis)

    private enum CodingKeys: String, CodingKey {
        case kind, branchName, remoteName, name, oid, basis
    }

    private enum Kind: String, Codable {
        case localDefaultBranch, originDefaultBranch, branch, commit, ref
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .localDefaultBranch:
            self = .localDefaultBranch(
                branchName: try container.decode(String.self, forKey: .branchName),
                basis: try container.decode(IPCBridgeReviewComparisonBasis.self, forKey: .basis)
            )
        case .originDefaultBranch:
            self = .originDefaultBranch(
                remoteName: try container.decode(String.self, forKey: .remoteName),
                branchName: try container.decode(String.self, forKey: .branchName),
                basis: try container.decode(IPCBridgeReviewComparisonBasis.self, forKey: .basis)
            )
        case .branch:
            self = .branch(
                name: try container.decode(String.self, forKey: .name),
                basis: try container.decode(IPCBridgeReviewComparisonBasis.self, forKey: .basis)
            )
        case .commit:
            let oid = try container.decode(String.self, forKey: .oid)
            let utf8 = oid.utf8
            guard utf8.count == 40 || utf8.count == 64,
                utf8.allSatisfy({ byte in
                    (byte >= 48 && byte <= 57)
                        || (byte >= 65 && byte <= 70)
                        || (byte >= 97 && byte <= 102)
                })
            else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath + [CodingKeys.oid],
                        debugDescription:
                            "Commit OID must contain exactly 40 or 64 hexadecimal characters"
                    )
                )
            }
            self = .commit(oid: oid)
        case .ref:
            self = .ref(
                name: try container.decode(String.self, forKey: .name),
                basis: try container.decode(IPCBridgeReviewComparisonBasis.self, forKey: .basis)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .localDefaultBranch(let branchName, let basis):
            try container.encode(Kind.localDefaultBranch, forKey: .kind)
            try container.encode(branchName, forKey: .branchName)
            try container.encode(basis, forKey: .basis)
        case .originDefaultBranch(let remoteName, let branchName, let basis):
            try container.encode(Kind.originDefaultBranch, forKey: .kind)
            try container.encode(remoteName, forKey: .remoteName)
            try container.encode(branchName, forKey: .branchName)
            try container.encode(basis, forKey: .basis)
        case .branch(let name, let basis):
            try container.encode(Kind.branch, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(basis, forKey: .basis)
        case .commit(let oid):
            try container.encode(Kind.commit, forKey: .kind)
            try container.encode(oid, forKey: .oid)
        case .ref(let name, let basis):
            try container.encode(Kind.ref, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(basis, forKey: .basis)
        }
    }
}

public enum IPCBridgeReviewComparisonOrigin: Codable, Equatable, Sendable {
    case contribution(IPCBridgeReviewContributionOrigin)

    private enum CodingKeys: String, CodingKey {
        case kind, baseRole, comparedRole, symbolicTarget
        case resolvedTargetOID, reviewedHeadOID, baseOID
    }

    private enum Kind: String, Codable {
        case contribution
    }

    private enum ComparedEndpointRole: String, Codable {
        case capturedWorkingTree
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .contribution:
            guard
                try container.decode(ComparedEndpointRole.self, forKey: .comparedRole)
                    == .capturedWorkingTree
            else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Comparison endpoint roles do not match contribution"
                    )
                )
            }
            self = .contribution(
                IPCBridgeReviewContributionOrigin(
                    symbolicTarget: try container.decode(
                        IPCBridgeReviewComparisonTarget.self,
                        forKey: .symbolicTarget
                    ),
                    resolvedTargetOID: try container.decode(String.self, forKey: .resolvedTargetOID),
                    reviewedHeadOID: try container.decode(String.self, forKey: .reviewedHeadOID),
                    baseRole: try container.decode(
                        IPCBridgeReviewComparisonBaseRole.self,
                        forKey: .baseRole
                    ),
                    baseOID: try container.decode(
                        String.self,
                        forKey: .baseOID
                    )
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .contribution(let origin):
            try container.encode(Kind.contribution, forKey: .kind)
            try container.encode(origin.baseRole, forKey: .baseRole)
            try container.encode(ComparedEndpointRole.capturedWorkingTree, forKey: .comparedRole)
            try container.encode(origin.symbolicTarget, forKey: .symbolicTarget)
            try container.encode(origin.resolvedTargetOID, forKey: .resolvedTargetOID)
            try container.encode(origin.reviewedHeadOID, forKey: .reviewedHeadOID)
            try container.encode(origin.baseOID, forKey: .baseOID)
        }
    }
}
