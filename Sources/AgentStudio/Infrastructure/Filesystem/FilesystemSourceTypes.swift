import Foundation

enum FilesystemSourceKind: Hashable, Sendable {
    case watchedParentMembership
}

struct FilesystemSourceID: Hashable, Sendable {
    let kind: FilesystemSourceKind
    let rootID: UUID
}

struct FSEventRegistrationToken: Hashable, Sendable {
    let sourceID: FilesystemSourceID
    let registrationGeneration: UInt64
    let rootGeneration: UInt64
}
