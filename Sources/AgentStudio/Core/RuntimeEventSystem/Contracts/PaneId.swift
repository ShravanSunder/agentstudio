import Foundation

/// Primary pane identity.
///
/// `PaneId` is the primary identity for a pane across state, views, and runtime routing.
/// A terminal's durable `ZmxSessionID` is an independent stored identity; it is not
/// derived from the pane ID. Surface IDs remain runtime associations.
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
/// - Use `PaneId.generateUUIDv7()` when minting a new pane identity.
/// - Use `PaneId(existingUUID:)` when preserving an already durable identity.
///   Historical UUID versions remain valid identities and are never rewritten.
struct PaneId: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {

    /// The underlying UUID. Newly minted values are v7; existing values may use any UUID version.
    let uuid: UUID

    // MARK: - Creation

    /// Mint a new time-ordered PaneId using UUID v7.
    static func generateUUIDv7() -> Self {
        Self(existingUUID: UUIDv7.generate())
    }

    /// Preserve an already durable UUID exactly, regardless of its historical version.
    init(existingUUID: UUID) {
        self.uuid = existingUUID
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

    /// Whether this PaneId uses UUID v7 and therefore carries a timestamp.
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
        "PaneId(\(uuid.uuidString))"
    }
}

// MARK: - Codable

extension PaneId: Codable {

    /// Decode and preserve an existing bare UUID string exactly.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        uuid = try container.decode(UUID.self)
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
