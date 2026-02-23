import Foundation

/// Primary pane identity. Time-ordered UUID v7 in canonical greenfield schema.
///
/// `PaneId` is the **only** primary identity in the pane system.
/// All other identifiers (zmx session names, surface IDs, stable keys)
/// are derived from or associated with a `PaneId`.
///
/// See: `session_lifecycle.md`, section "Identity Contract (Canonical)".
///
/// UUID v7 gives time-ordering at millisecond granularity: new panes
/// generally sort by creation time via standard string comparison.
/// IDs generated within the same millisecond may not sort by exact
/// creation order because low bits are random. The `hexPrefix` (first
/// 16 hex chars) encodes the timestamp for diagnostics and ordering checks.
///
/// Usage guidance:
/// - Use `PaneId()` when minting a new pane identity in production code.
/// - Use `PaneId(uuid:)` when wrapping an existing UUID that is already v7.
struct PaneId: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

    /// The underlying UUID (v7 in canonical flows).
    let uuid: UUID

    // MARK: - Creation

    /// Mint a new PaneId with UUID v7 (time-ordered).
    init() {
        self.uuid = UUIDv7.generate()
    }

    /// Wrap an existing UUID.
    /// Callers are expected to pass UUID v7 for canonical pane identity.
    init(uuid: UUID) {
        precondition(UUIDv7.isV7(uuid), "PaneId(uuid:) requires UUID v7 in canonical greenfield schema")
        self.uuid = uuid
    }

    // MARK: - Derived Identity

    /// The 16 lowercase hex character prefix.
    ///
    /// For UUID v7, this is the timestamp portion — useful for diagnostics
    /// and temporal ordering checks.
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

    /// The creation timestamp for UUID v7, otherwise nil.
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
        "PaneId(v7=\(isV7): \(uuid.uuidString))"
    }
}

// MARK: - Codable

extension PaneId: Codable {

    /// Decode from a bare UUID string and enforce canonical UUID v7 identity.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedUuid = try container.decode(UUID.self)
        guard UUIDv7.isV7(decodedUuid) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "PaneId must decode from UUID v7 in canonical greenfield schema"
            )
        }
        uuid = decodedUuid
    }

    /// Encode as a bare UUID string.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }
}

// MARK: - Comparable

extension PaneId: Comparable {

    /// Lexicographic comparison of UUID strings.
    /// For UUID v7, this approximates temporal ordering at millisecond granularity.
    /// IDs minted within the same millisecond may not preserve exact creation order.
    static func < (lhs: PaneId, rhs: PaneId) -> Bool {
        lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}
