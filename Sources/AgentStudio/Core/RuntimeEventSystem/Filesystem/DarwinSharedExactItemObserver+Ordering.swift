import CoreServices
import Foundation

extension DarwinSharedExactItemObserverRegistry {
    package static func sortWorktreeIds(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    package static func sortParentKeys(
        _ lhs: DarwinSharedExactItemParentKey,
        _ rhs: DarwinSharedExactItemParentKey
    ) -> Bool {
        if lhs.volumeSystemNumber != rhs.volumeSystemNumber {
            return lhs.volumeSystemNumber < rhs.volumeSystemNumber
        }
        return lhs.parentPath < rhs.parentPath
    }

    static func isRootChange(_ event: DarwinSharedExactItemRawEvent) -> Bool {
        event.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
    }
}
