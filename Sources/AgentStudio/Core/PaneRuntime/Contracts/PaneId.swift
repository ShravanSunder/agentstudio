import Foundation

/// Primary pane identity. Time-ordered (UUID v7) for new panes,
/// backward-compatible with existing UUID v4 from persisted state.
///
/// `PaneId` is the **only** primary identity in the pane system.
/// All other identifiers (zmx session names, surface IDs, stable keys)
/// are derived from or associated with a `PaneId`.
///
/// See: `session_lifecycle.md#identity-contract-canonical`
///
/// UUID v7 gives time-ordering at millisecond granularity: new panes
/// generally sort by creation time via standard string comparison.
/// IDs generated within the same millisecond may not sort by exact
/// creation order because low bits are random. The `hexPrefix` (first
/// 16 hex chars) encodes the timestamp, making zmx session names debuggable.
///
/// Codable encodes as a bare UUID string for backward compatibility
/// with workspaces persisted under the old `typealias PaneId = UUID`.
struct PaneId: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

    /// The underlying UUID. v7 for new panes, v4 for deserialized legacy panes.
    let uuid: UUID

    // MARK: - Creation

    /// Mint a new PaneId with UUID v7 (time-ordered).
    init() {
        self.uuid = UUIDv7.generate()
    }

    /// Wrap an existing UUID (deserialization, migration, tests).
    init(uuid: UUID) {
        self.uuid = uuid
    }

    // MARK: - Derived Identity

    /// The 16 lowercase hex character prefix used in zmx session name segments.
    ///
    /// For UUID v7, this is the timestamp portion — sortable and debuggable
    /// in `zmx ls` output. For legacy UUID v4, it's the first 8 bytes in hex.
    ///
    /// Derivation: `first16hex(lowercase(removeHyphens(uuid.uuidString)))`
    var hexPrefix: String {
        String(
            uuid.uuidString
                .replacingOccurrences(of: "-", with: "")
                .prefix(16)
        ).lowercased()
    }

    /// The full 32-character lowercase hex representation (no hyphens).
    var fullHex: String {
        uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Whether this PaneId was generated with UUID v7 (has timestamp).
    var isV7: Bool {
        UUIDv7.isV7(uuid)
    }

    /// The creation timestamp, if this is a UUID v7. Nil for legacy v4 IDs.
    var createdAt: Date? {
        UUIDv7.timestamp(from: uuid)
    }

    // MARK: - String Representations

    /// Standard UUID string (e.g., "0191F5D4-9B2A-7C3D-8E4F-0123456789AB").
    var uuidString: String {
        uuid.uuidString
    }

    var description: String {
        uuid.uuidString
    }

    var debugDescription: String {
        let version = isV7 ? "v7" : "v4"
        return "PaneId(\(version): \(uuid.uuidString))"
    }
}

// MARK: - Codable

extension PaneId: Codable {

    /// Decode from a bare UUID string — backward compatible with `UUID` encoding.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        uuid = try container.decode(UUID.self)
    }

    /// Encode as a bare UUID string — backward compatible with `UUID` encoding.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }
}

// MARK: - Comparable

extension PaneId: Comparable {

    /// Lexicographic comparison of UUID strings. For UUID v7, this is
    /// temporal ordering (earlier creation time sorts first).
    static func < (lhs: PaneId, rhs: PaneId) -> Bool {
        lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}
