import CryptoKit
import Foundation

enum BridgeContentHandleIdentity {
    static func handleId(
        endpointId: String,
        itemId: String,
        role: BridgeContentHandle.Role,
        contentHash: String
    ) -> String {
        let identity = "\(endpointId):\(itemId):\(role.rawValue):\(contentHash)"
        return "handle-\(sha256Hex(identity))"
    }

    static func resourceUrl(
        handleId: String,
        reviewGeneration: BridgeReviewGeneration
    ) -> String {
        "agentstudio://resource/review/content/\(handleId)?generation=\(reviewGeneration.rawValue)"
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
