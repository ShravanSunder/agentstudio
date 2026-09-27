import Foundation
import GRDB

package enum BridgeReceiverStorageError: Error, Equatable, Sendable {
    case malformedRow(String)
    case retiredReceiver
    case staleGeneration
    case missingMemberReference
}

/// A wall-time anchor driven by an injected monotonic clock. Tests can move a
/// controlled clock across the retention deadline without sleeping.
package struct BridgeReceiverRetirementTime<ClockType: Clock> where ClockType.Duration == Duration {
    package let clock: ClockType
    package let anchorInstant: ClockType.Instant
    package let anchorDate: Date

    package init(clock: ClockType, anchorDate: Date) {
        self.clock = clock
        self.anchorInstant = clock.now
        self.anchorDate = anchorDate
    }

    package var now: Date {
        let elapsed = anchorInstant.duration(to: clock.now).components
        return anchorDate.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
}

/// Canonical keys for state rows. Paths are byte-length prefixed so no path can
/// collide with a structural key or another typed identity.
package enum BridgeReceiverStateKeyCodec {
    package static let singleton = "singleton"

    package static func member(_ worktreeID: UUID) -> String {
        BridgePaneLinkItemKeyCodec.member(worktreeID)
    }

    package static func document(_ location: BridgeDocumentLocation) -> String {
        let path = location.canonicalPath
        return "document:\(path.utf8.count):\(path)"
    }

    package static func decodeDocument(_ key: String) throws -> BridgeDocumentLocation {
        guard key.hasPrefix("document:") else { throw BridgeReceiverStorageError.malformedRow("document key") }
        let suffix = key.dropFirst("document:".count)
        guard let separator = suffix.firstIndex(of: ":"),
            let byteCount = Int(suffix[..<separator]),
            let location = BridgeDocumentLocation(canonicalPath: String(suffix[suffix.index(after: separator)...])),
            location.canonicalPath.utf8.count == byteCount,
            document(location) == key
        else { throw BridgeReceiverStorageError.malformedRow("document key") }
        return location
    }
}

/// A typed row projection. A deleted row keeps its identity and generation,
/// but its value columns are ignored until a newer keyed write replaces it.
struct BridgeReceiverStateRow: Equatable, Sendable {
    let receiver: BridgeReceiver
    let kind: String
    let itemKey: String
    let generation: Int
    let isDeleted: Bool
    var textValue: String?
    var worktreeID: UUID?
    var forgeHost: String?
    var forgeOwner: String?
    var forgeRepository: String?
    var forgeNumber: Int?
    var documentPath: String?
    var provenanceRepoID: UUID?
    var provenanceWorktreeID: UUID?
    var provenanceRelativePath: String?
    var comparisonKind: String?
    var comparisonBasis: String?
    var comparisonName: String?
    var comparisonBranch: String?
    var comparisonRemote: String?
    var comparisonOID: String?
    var ordinal: Int?
    var importedVariant: String?
    var importedPayload: String?
}

struct BridgeReceiverItemRow: Equatable, Sendable {
    let receiver: BridgeReceiver
    let kind: String
    let itemKey: String
    let contributorKey: String
    let generation: Int
    let isDeleted: Bool
    var worktreeID: UUID?
    var forgeHost: String?
    var forgeOwner: String?
    var forgeRepository: String?
    var forgeNumber: Int?
    var contributorKind: String?
    var contributorProvider: String?
    var contributorSessionRef: String?
    var addedAt: Date?
}

extension BridgeReceiverStateRow {
    func withGeneration(_ generation: Int, isDeleted: Bool = false) -> Self {
        var copy = Self(receiver: receiver, kind: kind, itemKey: itemKey, generation: generation, isDeleted: isDeleted)
        copy.textValue = textValue
        copy.worktreeID = worktreeID
        copy.forgeHost = forgeHost
        copy.forgeOwner = forgeOwner
        copy.forgeRepository = forgeRepository
        copy.forgeNumber = forgeNumber
        copy.documentPath = documentPath
        copy.provenanceRepoID = provenanceRepoID
        copy.provenanceWorktreeID = provenanceWorktreeID
        copy.provenanceRelativePath = provenanceRelativePath
        copy.comparisonKind = comparisonKind
        copy.comparisonBasis = comparisonBasis
        copy.comparisonName = comparisonName
        copy.comparisonBranch = comparisonBranch
        copy.comparisonRemote = comparisonRemote
        copy.comparisonOID = comparisonOID
        copy.ordinal = ordinal
        copy.importedVariant = importedVariant
        copy.importedPayload = importedPayload
        return copy
    }
}

extension BridgeReceiverItemRow {
    func withGeneration(_ generation: Int, isDeleted: Bool = false) -> Self {
        var copy = Self(
            receiver: receiver, kind: kind, itemKey: itemKey, contributorKey: contributorKey,
            generation: generation, isDeleted: isDeleted)
        copy.worktreeID = worktreeID
        copy.forgeHost = forgeHost
        copy.forgeOwner = forgeOwner
        copy.forgeRepository = forgeRepository
        copy.forgeNumber = forgeNumber
        copy.contributorKind = contributorKind
        copy.contributorProvider = contributorProvider
        copy.contributorSessionRef = contributorSessionRef
        copy.addedAt = addedAt
        return copy
    }
}
