import Foundation

/// Request-scoped Review picker data. These values are content payloads, never
/// part of pane presentation or a metadata subscription.
package enum BridgeReviewComparisonBranchTarget: Codable, Equatable, Sendable {
    case local(branchName: String, oid: String)
    case remoteTracking(remoteName: String, branchName: String, oid: String)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case branchName
        case kind
        case oid
        case remoteName
    }

    private enum Kind: String, Codable {
        case local
        case remoteTracking
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .local:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.branchName.rawValue, CodingKeys.kind.rawValue, CodingKeys.oid.rawValue],
                contract: "local Review comparison branch target"
            )
            self = .local(
                branchName: try container.decode(String.self, forKey: .branchName),
                oid: try container.decode(String.self, forKey: .oid)
            )
        case .remoteTracking:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
                contract: "remote-tracking Review comparison branch target"
            )
            self = .remoteTracking(
                remoteName: try container.decode(String.self, forKey: .remoteName),
                branchName: try container.decode(String.self, forKey: .branchName),
                oid: try container.decode(String.self, forKey: .oid)
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .local(let branchName, let oid):
            try container.encode(branchName, forKey: .branchName)
            try container.encode(Kind.local, forKey: .kind)
            try container.encode(oid, forKey: .oid)
        case .remoteTracking(let remoteName, let branchName, let oid):
            try container.encode(branchName, forKey: .branchName)
            try container.encode(Kind.remoteTracking, forKey: .kind)
            try container.encode(oid, forKey: .oid)
            try container.encode(remoteName, forKey: .remoteName)
        }
    }

    package var canonicalReferenceName: String {
        switch self {
        case .local(let branchName, _): "refs/heads/\(branchName)"
        case .remoteTracking(let remoteName, let branchName, _):
            "refs/remotes/\(remoteName)/\(branchName)"
        }
    }
}

package struct BridgeReviewComparisonTargetCatalog: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case branches
        case capturedAtUnixMilliseconds
        case cutoffUnixMilliseconds
        case currentTarget
        case defaultTarget
        case isTruncated
    }

    let capturedAtUnixMilliseconds: Int64
    let cutoffUnixMilliseconds: Int64
    let isTruncated: Bool
    let defaultTarget: BridgeReviewComparisonBranchTarget?
    let currentTarget: BridgeReviewComparisonBranchTarget?
    let branches: [BridgeReviewComparisonBranchTarget]

    /// Compatibility initializer used only by old fixture construction. The
    /// request-scoped wire result always supplies capture facts explicitly.
    package init(
        defaultTarget: BridgeReviewComparisonBranchTarget?,
        branches: [BridgeReviewComparisonBranchTarget]
    ) {
        self.init(
            capturedAtUnixMilliseconds: 0,
            cutoffUnixMilliseconds: 0,
            isTruncated: false,
            defaultTarget: defaultTarget,
            currentTarget: nil,
            branches: branches
        )
    }

    package init(
        capturedAtUnixMilliseconds: Int64,
        cutoffUnixMilliseconds: Int64,
        isTruncated: Bool,
        defaultTarget: BridgeReviewComparisonBranchTarget?,
        currentTarget: BridgeReviewComparisonBranchTarget?,
        branches: [BridgeReviewComparisonBranchTarget]
    ) {
        self.capturedAtUnixMilliseconds = capturedAtUnixMilliseconds
        self.cutoffUnixMilliseconds = cutoffUnixMilliseconds
        self.isTruncated = isTruncated
        self.defaultTarget = defaultTarget
        self.currentTarget = currentTarget
        self.branches = branches
    }

    package init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review comparison target catalog content"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.capturedAtUnixMilliseconds = try container.decode(Int64.self, forKey: .capturedAtUnixMilliseconds)
        self.cutoffUnixMilliseconds = try container.decode(Int64.self, forKey: .cutoffUnixMilliseconds)
        self.isTruncated = try container.decode(Bool.self, forKey: .isTruncated)
        self.defaultTarget = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeReviewComparisonBranchTarget.self,
            forKey: .defaultTarget,
            from: container,
            codingPath: decoder.codingPath
        )
        self.currentTarget = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeReviewComparisonBranchTarget.self,
            forKey: .currentTarget,
            from: container,
            codingPath: decoder.codingPath
        )
        self.branches = try container.decode([BridgeReviewComparisonBranchTarget].self, forKey: .branches)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(branches, forKey: .branches)
        try container.encode(capturedAtUnixMilliseconds, forKey: .capturedAtUnixMilliseconds)
        try container.encode(cutoffUnixMilliseconds, forKey: .cutoffUnixMilliseconds)
        try container.encode(currentTarget, forKey: .currentTarget)
        try container.encode(defaultTarget, forKey: .defaultTarget)
        try container.encode(isTruncated, forKey: .isTruncated)
    }
}
