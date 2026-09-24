import Foundation

/// A session's subject as the page sees it: the member worktree whose
/// Files group lists it, or the canonical location of a local document.
/// Repository identity stays native.
enum BridgeProductWorktreeAnnotationSubject: Codable, Hashable, Sendable {
    case git(worktreeId: String)
    case localFile(documentLocation: String)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case documentLocation
        case kind
        case worktreeId
    }

    private enum Kind: String, Codable {
        case git
        case localFile
    }

    init(_ subject: WorktreeAnnotationSubject) {
        switch subject {
        case .git(_, let worktreeID):
            self = .git(worktreeId: worktreeID)
        case .localFile(let location):
            self = .localFile(documentLocation: location.canonicalPath)
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation subject"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .git:
            let worktreeId = try container.decode(String.self, forKey: .worktreeId)
            try BridgeProductContractDecoding.validateIdentifier(worktreeId, codingPath: decoder.codingPath)
            guard !container.contains(.documentLocation) else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Annotation Git subject is invalid",
                    codingPath: decoder.codingPath
                )
            }
            self = .git(worktreeId: worktreeId)
        case .localFile:
            let documentLocation = try container.decode(String.self, forKey: .documentLocation)
            try BridgeProductContractDecoding.validateDisplayPath(documentLocation, codingPath: decoder.codingPath)
            guard documentLocation.hasPrefix("/"), !container.contains(.worktreeId) else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Annotation local-file subject is invalid",
                    codingPath: decoder.codingPath
                )
            }
            self = .localFile(documentLocation: documentLocation)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .git(let worktreeId):
            try container.encode(Kind.git, forKey: .kind)
            try container.encode(worktreeId, forKey: .worktreeId)
        case .localFile(let documentLocation):
            try container.encode(Kind.localFile, forKey: .kind)
            try container.encode(documentLocation, forKey: .documentLocation)
        }
    }
}
