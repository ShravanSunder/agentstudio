import AgentStudioInfrastructure
import Foundation

/// Give an accepted Open files entry a UUIDv7 key strictly newer than the
/// receiver's previous logical millisecond, even when wall time has not moved.
/// The caller owns and serializes the floor; this function owns no state.
package func mintOpenedDocumentSortKey(
    wallMillis: UInt64, floorMillis: UInt64
) -> (key: UUID, newFloorMillis: UInt64) {
    let nextMillis = max(wallMillis, floorMillis + 1)
    precondition(nextMillis < (1 << 48), "UUIDv7 millisecond field exhausted")
    return (UUIDv7.generate(milliseconds: nextMillis), nextMillis)
}

/// Read the ordering field without interpreting it as a user-visible time.
package func openedDocumentSortKeyMillis(_ key: UUID) -> UInt64? {
    guard UUIDv7.isV7(key) else { return nil }
    let bytes = key.uuid
    return (UInt64(bytes.0) << 40) | (UInt64(bytes.1) << 32)
        | (UInt64(bytes.2) << 24) | (UInt64(bytes.3) << 16)
        | (UInt64(bytes.4) << 8) | UInt64(bytes.5)
}
