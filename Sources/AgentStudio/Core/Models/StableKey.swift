import CryptoKit
import Foundation

enum StableKey {
    /// Derive a 16-char hex key from a filesystem path via SHA-256.
    /// Resolves symlinks for canonical identity. 64 bits of entropy.
    static func fromPath(_ url: URL) -> String {
        let canonical = url.resolvingSymlinksInPath().path
        let hash = SHA256.hash(data: Data(canonical.utf8))
        return Array(hash.prefix(8)).map { String(format: "%02x", $0) }.joined()
    }
}
