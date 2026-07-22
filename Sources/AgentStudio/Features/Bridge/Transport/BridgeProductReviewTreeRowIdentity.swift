import CryptoKit
import Foundation

enum BridgeProductReviewTreeRowIdentity {
    static func directoryRowId(path: String) -> String {
        "review-directory-\(sha256Hex(path).prefix(32))"
    }

    static func itemRowId(itemId: String) -> String {
        "review-row-\(sha256Hex(itemId).prefix(32))"
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
