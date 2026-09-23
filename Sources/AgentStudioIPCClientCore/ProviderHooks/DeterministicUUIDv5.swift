import CryptoKit
import Foundation

/// RFC 4122 name-based (version 5) identifiers.
///
/// A provider may retry the same hook invocation. Deriving the occurrence
/// identity from the provider's own conversation, turn and event names means a
/// retry carries the identity it carried the first time, so Sessions
/// deduplicates it instead of recording it twice.
package enum DeterministicUUIDv5 {
    /// Fixed namespace for every Agent Studio provider hook projection. It is a
    /// literal because changing it would renumber every identity ever derived.
    package static let providerHookNamespace: [UInt8] = [
        0x6F, 0x1B, 0x2C, 0x74, 0x9A, 0x4D, 0x5E, 0x11,
        0xB4, 0x3C, 0x2E, 0x8D, 0x71, 0x0A, 0x5F, 0x92,
    ]

    package static func providerHookIdentifier(name: String) -> UUID {
        identifier(namespace: providerHookNamespace, name: name)
    }

    package static func identifier(namespace: [UInt8], name: String) -> UUID {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data(namespace))
        hasher.update(data: Data(name.utf8))
        var digest = Array(hasher.finalize().prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                digest[0], digest[1], digest[2], digest[3],
                digest[4], digest[5], digest[6], digest[7],
                digest[8], digest[9], digest[10], digest[11],
                digest[12], digest[13], digest[14], digest[15]
            )
        )
    }
}
