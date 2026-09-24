import Foundation

/// One member worktree of a receiver's Files collection and the group path its
/// files are listed under.
///
/// A member-relative path inside one of `nestedMemberRelativeRoots` belongs to
/// that deeper member's group, never to this one. `identityPrefix` namespaces
/// the member's own descriptor identities in the collection, so a member-scoped
/// identity (as annotations store it) maps to the identity the page sees.
struct BridgeProductFileMemberGroup: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case groupPath
        case identityPrefix
        case nestedMemberRelativeRoots
        case worktreeId
    }

    let groupPath: String
    let identityPrefix: String
    let nestedMemberRelativeRoots: [String]
    /// The member's worktree id as a lowercased UUID string.
    let worktreeId: String

    init(
        groupPath: String,
        identityPrefix: String,
        nestedMemberRelativeRoots: [String],
        worktreeId: String
    ) throws {
        self.groupPath = groupPath
        self.identityPrefix = identityPrefix
        self.nestedMemberRelativeRoots = nestedMemberRelativeRoots
        self.worktreeId = worktreeId
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File member group"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.groupPath = try container.decode(String.self, forKey: .groupPath)
        self.identityPrefix = try container.decode(String.self, forKey: .identityPrefix)
        self.nestedMemberRelativeRoots = try container.decode(
            [String].self,
            forKey: .nestedMemberRelativeRoots
        )
        self.worktreeId = try container.decode(String.self, forKey: .worktreeId)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupPath, forKey: .groupPath)
        try container.encode(identityPrefix, forKey: .identityPrefix)
        try container.encode(nestedMemberRelativeRoots, forKey: .nestedMemberRelativeRoots)
        try container.encode(worktreeId, forKey: .worktreeId)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateDisplayPath(groupPath, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(identityPrefix, codingPath: codingPath)
        try BridgeProductContractDecoding.validateMaximum(
            nestedMemberRelativeRoots.count,
            maximum: BridgeProductWireContract.maximumFileCollectionMemberGroupCount,
            name: "File member group nested-root count",
            codingPath: codingPath
        )
        for root in nestedMemberRelativeRoots {
            try BridgeProductContractDecoding.validateDisplayPath(root, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateIdentifier(worktreeId, codingPath: codingPath)
    }
}

/// One opened document outside every member worktree, listed under the
/// collection's opened-documents group. `documentLocation` is the document's
/// canonical path, the identity its local annotations are recorded under;
/// `displayPath` is the key the page lists it by.
struct BridgeProductFileOpenedDocumentEntry: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case displayPath
        case documentLocation
        case identityPrefix
    }

    let displayPath: String
    let documentLocation: String
    let identityPrefix: String

    init(displayPath: String, documentLocation: String, identityPrefix: String) throws {
        self.displayPath = displayPath
        self.documentLocation = documentLocation
        self.identityPrefix = identityPrefix
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File opened-document entry"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayPath = try container.decode(String.self, forKey: .displayPath)
        self.documentLocation = try container.decode(String.self, forKey: .documentLocation)
        self.identityPrefix = try container.decode(String.self, forKey: .identityPrefix)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayPath, forKey: .displayPath)
        try container.encode(documentLocation, forKey: .documentLocation)
        try container.encode(identityPrefix, forKey: .identityPrefix)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateDisplayPath(displayPath, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(identityPrefix, codingPath: codingPath)
        try BridgeProductContractDecoding.validateDisplayPath(documentLocation, codingPath: codingPath)
        guard documentLocation.hasPrefix("/") else {
            throw BridgeProductContractDecoding.invalidValue(
                "File opened-document location must be a canonical absolute path",
                codingPath: codingPath
            )
        }
    }
}

/// The complete member-group list of a Files collection. It replaces the
/// previous list and is sent after the source is accepted and after every
/// membership change, so a worktree-relative location can be mapped to its
/// display key even while the tree itself is filtered. The opened documents
/// outside every member ride along, so a local-file annotation can be mapped
/// to its document's display key the same way.
///
/// `source` and `membershipRevision` order the lists: a list from a superseded
/// source or an older membership never replaces a newer one.
struct BridgeProductFileMemberGroupsEvent: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventKind
        case groups
        case membershipRevision
        case openedDocuments
        case source
    }

    let groups: [BridgeProductFileMemberGroup]
    let membershipRevision: Int
    let openedDocuments: [BridgeProductFileOpenedDocumentEntry]
    let source: BridgeProductFileSourceIdentity

    init(
        groups: [BridgeProductFileMemberGroup],
        membershipRevision: Int,
        openedDocuments: [BridgeProductFileOpenedDocumentEntry],
        source: BridgeProductFileSourceIdentity
    ) throws {
        self.groups = groups
        self.openedDocuments = openedDocuments
        self.membershipRevision = membershipRevision
        self.source = source
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File member-groups event"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .eventKind) == "file.memberGroups" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File member-groups event kind",
                codingPath: decoder.codingPath
            )
        }
        self.groups = try container.decode([BridgeProductFileMemberGroup].self, forKey: .groups)
        self.membershipRevision = try container.decode(Int.self, forKey: .membershipRevision)
        self.openedDocuments = try container.decode(
            [BridgeProductFileOpenedDocumentEntry].self,
            forKey: .openedDocuments
        )
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.memberGroups", forKey: .eventKind)
        try container.encode(groups, forKey: .groups)
        try container.encode(membershipRevision, forKey: .membershipRevision)
        try container.encode(openedDocuments, forKey: .openedDocuments)
        try container.encode(source, forKey: .source)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateNonnegative(
            membershipRevision,
            name: "membershipRevision",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            groups.count,
            maximum: BridgeProductWireContract.maximumFileCollectionMemberGroupCount,
            name: "File member group count",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            openedDocuments.count,
            maximum: BridgeProductWireContract.maximumFileCollectionOpenedDocumentCount,
            name: "File opened-document count",
            codingPath: codingPath
        )
        guard Set(openedDocuments.map(\.documentLocation)).count == openedDocuments.count,
            Set(openedDocuments.map(\.displayPath)).count == openedDocuments.count
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "File opened documents must name each location and display path once",
                codingPath: codingPath
            )
        }
        guard Set(groups.map(\.worktreeId)).count == groups.count,
            Set(groups.map(\.groupPath)).count == groups.count
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "File member groups must name each worktree and group path once",
                codingPath: codingPath
            )
        }
    }
}
