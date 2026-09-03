import AgentStudioInfrastructure
import CryptoKit
import Foundation

enum BridgeOperationCorrelation {
    /// Mints an owner-local UUIDv7 and returns only its scrubbed wire value.
    static func mintScrubbedID() -> String {
        let ownerLocalIdentity = UUIDv7.generate()
        return SHA256.hash(data: Data(ownerLocalIdentity.uuidString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
