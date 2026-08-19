import Foundation

struct BridgeProductWorktreeAnnotationCommandRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operation
    }

    let operation: BridgeProductWorktreeAnnotationOperation

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation command request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.operation = try container.decode(
            BridgeProductWorktreeAnnotationOperation.self,
            forKey: .operation
        )
    }

    func validateSource(surface: BridgeProductSurface, codingPath: [any CodingKey]) throws {
        guard case .createRoot(_, _, _, let origin) = operation else { return }
        try origin.validate(surface: surface, codingPath: codingPath)
    }
}

enum BridgeProductWorktreeAnnotationCommandResult: Codable, Equatable, Sendable {
    case completed(BridgeProductWorktreeAnnotationCommandOutcomeDTO)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case outcome
    }

    private enum Kind: String, Codable {
        case completed
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation command result"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .completed:
            self = .completed(
                try container.decode(
                    BridgeProductWorktreeAnnotationCommandOutcomeDTO.self,
                    forKey: .outcome
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .completed(let outcome):
            try container.encode(Kind.completed, forKey: .kind)
            try container.encode(outcome, forKey: .outcome)
        }
    }
}
