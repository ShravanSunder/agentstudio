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
