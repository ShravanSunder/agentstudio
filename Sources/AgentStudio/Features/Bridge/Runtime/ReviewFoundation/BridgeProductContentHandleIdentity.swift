import CryptoKit
import Foundation

enum BridgeProductContentHandleIdentity {
    static func handleId(
        endpointId: String,
        itemId: String,
        role: BridgeContentHandle.Role,
        contentHash: String
    ) -> String {
        let identity = "\(endpointId):\(itemId):\(role.rawValue):\(contentHash)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        return "handle-\(digest.map { String(format: "%02x", $0) }.joined())"
    }
}
