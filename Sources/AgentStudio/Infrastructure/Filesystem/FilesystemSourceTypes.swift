import Foundation

package enum FilesystemSourceKind: Hashable, Sendable {
    case watchedParentMembership
}

package struct FilesystemSourceID: Hashable, Sendable {
    package let kind: FilesystemSourceKind
    package let rootID: UUID

    package init(kind: FilesystemSourceKind, rootID: UUID) {
        self.kind = kind
        self.rootID = rootID
    }
}

package struct FSEventRegistrationToken: Hashable, Sendable {
    package let sourceID: FilesystemSourceID
    package let registrationGeneration: UInt64
    package let rootGeneration: UInt64

    package init(
        sourceID: FilesystemSourceID,
        registrationGeneration: UInt64,
        rootGeneration: UInt64
    ) {
        self.sourceID = sourceID
        self.registrationGeneration = registrationGeneration
        self.rootGeneration = rootGeneration
    }
}
