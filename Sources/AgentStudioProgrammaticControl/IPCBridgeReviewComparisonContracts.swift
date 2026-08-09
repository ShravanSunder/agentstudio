public enum IPCBridgeReviewComparisonTarget: Codable, Equatable, Sendable {
    case localDefaultBranch(branchName: String)
    case originDefaultBranch(remoteName: String, branchName: String)
    case branch(name: String)
    case commit(oid: String)
    case ref(name: String)

    private enum CodingKeys: String, CodingKey {
        case kind, branchName, remoteName, name, oid
    }

    private enum Kind: String, Codable {
        case localDefaultBranch, originDefaultBranch, branch, commit, ref
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .localDefaultBranch:
            self = .localDefaultBranch(
                branchName: try container.decode(String.self, forKey: .branchName)
            )
        case .originDefaultBranch:
            self = .originDefaultBranch(
                remoteName: try container.decode(String.self, forKey: .remoteName),
                branchName: try container.decode(String.self, forKey: .branchName)
            )
        case .branch:
            self = .branch(name: try container.decode(String.self, forKey: .name))
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
            self = .ref(name: try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .localDefaultBranch(let branchName):
            try container.encode(Kind.localDefaultBranch, forKey: .kind)
            try container.encode(branchName, forKey: .branchName)
        case .originDefaultBranch(let remoteName, let branchName):
            try container.encode(Kind.originDefaultBranch, forKey: .kind)
            try container.encode(remoteName, forKey: .remoteName)
            try container.encode(branchName, forKey: .branchName)
        case .branch(let name):
            try container.encode(Kind.branch, forKey: .kind)
            try container.encode(name, forKey: .name)
        case .commit(let oid):
            try container.encode(Kind.commit, forKey: .kind)
            try container.encode(oid, forKey: .oid)
        case .ref(let name):
            try container.encode(Kind.ref, forKey: .kind)
            try container.encode(name, forKey: .name)
        }
    }
}

public enum IPCBridgeReviewComparisonOrigin: Codable, Equatable, Sendable {
    case contribution(
        symbolicTarget: IPCBridgeReviewComparisonTarget,
        resolvedTargetOID: String,
        reviewedHeadOID: String,
        contributionBaseOID: String
    )

    private enum CodingKeys: String, CodingKey {
        case kind, baseRole, comparedRole, symbolicTarget
        case resolvedTargetOID, reviewedHeadOID, contributionBaseOID
    }

    private enum Kind: String, Codable {
        case contribution
    }

    private enum EndpointRole: String, Codable {
        case contributionBase
        case capturedWorkingTree
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .contribution:
            guard
                try container.decode(EndpointRole.self, forKey: .baseRole) == .contributionBase,
                try container.decode(EndpointRole.self, forKey: .comparedRole)
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
                symbolicTarget: try container.decode(
                    IPCBridgeReviewComparisonTarget.self,
                    forKey: .symbolicTarget
                ),
                resolvedTargetOID: try container.decode(String.self, forKey: .resolvedTargetOID),
                reviewedHeadOID: try container.decode(String.self, forKey: .reviewedHeadOID),
                contributionBaseOID: try container.decode(
                    String.self,
                    forKey: .contributionBaseOID
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .contribution(
            let symbolicTarget,
            let resolvedTargetOID,
            let reviewedHeadOID,
            let contributionBaseOID
        ):
            try container.encode(Kind.contribution, forKey: .kind)
            try container.encode(EndpointRole.contributionBase, forKey: .baseRole)
            try container.encode(EndpointRole.capturedWorkingTree, forKey: .comparedRole)
            try container.encode(symbolicTarget, forKey: .symbolicTarget)
            try container.encode(resolvedTargetOID, forKey: .resolvedTargetOID)
            try container.encode(reviewedHeadOID, forKey: .reviewedHeadOID)
            try container.encode(contributionBaseOID, forKey: .contributionBaseOID)
        }
    }
}
