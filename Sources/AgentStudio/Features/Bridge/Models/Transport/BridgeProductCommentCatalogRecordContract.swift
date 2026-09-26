import Foundation

/// The batch part's key is derived from the entry identity. The record revision
/// is minted by N10 for the current install, independently of the entry's
/// per-row semantic revision in SQLite.
struct BridgeProductCommentCatalogRecord: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case entry
        case revision
    }

    let entry: WorktreeAnnotationCatalogEntry
    let revision: Int

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "comment catalog batch record"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try container.decode(WorktreeAnnotationCatalogEntry.self, forKey: .entry)
        revision = try container.decode(Int.self, forKey: .revision)
        try BridgeProductContractDecoding.validatePositive(
            revision,
            name: "revision",
            codingPath: decoder.codingPath
        )
    }

    var recordKey: String {
        switch entry {
        case .session(let session): "session:\(session.sessionID.rawValue.uuidString.lowercased())"
        case .thread(let thread): "thread:\(thread.threadID.rawValue.uuidString.lowercased())"
        case .message(let message): "message:\(message.messageID.rawValue.uuidString.lowercased())"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entry, forKey: .entry)
        try container.encode(revision, forKey: .revision)
    }
}
