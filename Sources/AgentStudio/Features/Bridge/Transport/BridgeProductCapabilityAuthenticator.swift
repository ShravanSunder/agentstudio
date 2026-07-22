import CryptoKit
import Foundation

/// Validates a presented pane capability independently of session lifecycle.
///
/// The router retains this digest when a transport installation is cleared so
/// an authenticated request can still be distinguished from an unauthorized
/// request without retaining the retired session or reading the request body.
struct BridgeProductCapabilityAuthenticator: Sendable {
    private let capabilityDigest: Data

    init(encodedCapability: String) {
        self.capabilityDigest = Self.digest(Data(encodedCapability.utf8))
    }

    func matches(_ presentedCapability: String) -> Bool {
        guard presentedCapability.utf8.count == 43 else { return false }
        let presentedDigest = Self.digest(Data(presentedCapability.utf8))
        guard presentedDigest.count == capabilityDigest.count else { return false }
        return zip(presentedDigest, capabilityDigest).reduce(UInt8(0)) { difference, pair in
            difference | (pair.0 ^ pair.1)
        } == 0
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
